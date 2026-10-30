#include "gtk_view_retirement.h"

#include <atomic>
#include <vector>

namespace {
#ifdef BUSYBOOKS_VIEW_RETIREMENT_DIAGNOSTICS
struct Counters {
  std::atomic<guint> active_bindings{0};
  std::atomic<guint> retiring_views{0};
  std::atomic<guint> retained_widgets{0};
  std::atomic<guint> application_holds{0};
  std::atomic<guint> pending_releases{0};
  std::atomic<guint> pending_finalizations{0};
  std::atomic<guint> retired_views{0};
  std::atomic<guint> released_views{0};
  std::atomic<guint> last_normal_references{0};
  std::atomic<guint> contract_violations{0};
} counters;
#define RECORD_COUNTER(statement) do { statement; } while (false)
#else
#define RECORD_COUNTER(statement) do {} while (false)
#endif

struct Retirement {
  GApplication* application;
  GtkWidget* view;
  GThread* gtk_thread;
  std::vector<GtkWidget*> descendants;
  std::atomic<bool> queued{false};
  std::atomic<bool> violated{false};
  guint pending_finalizations = 0;
  bool parent_finalized = false;
  bool own_refs_released = false;
  bool release_in_progress = false;
};

struct FinalizationObservation {
  Retirement* retirement;
  bool parent;
};
using FinalizationObservers = std::vector<FinalizationObservation>;

GQuark BindingQuark() {
  return g_quark_from_static_string("busybooks-gtk-view-retirement");
}

void EmbeddedViewRealized(GtkWidget* view, gpointer) {
  auto* window = gtk_widget_get_toplevel(view);
  if (!GTK_IS_WINDOW(window)) return;
  const auto delete_event = g_signal_lookup("delete-event", GTK_TYPE_WIDGET);
  g_signal_handlers_disconnect_matched(window,
      static_cast<GSignalMatchType>(G_SIGNAL_MATCH_ID | G_SIGNAL_MATCH_DATA),
      delete_event, 0, nullptr, nullptr, view);
}

void Trace(const char* stage, const Retirement* retirement) {
#ifdef BUSYBOOKS_VIEW_RETIREMENT_DIAGNOSTICS
  if (g_strcmp0(g_getenv("BUSYBOOKS_VIEW_RETIREMENT_DIAGNOSTICS"), "1") != 0) {
    return;
  }
  g_message("view-retirement stage=%s view=%p descendants=%zu bindings=%u retiring=%u "
            "retained=%u holds=%u pending=%u finalizers=%u violations=%u",
            stage, static_cast<void*>(retirement->view),
            retirement->descendants.size(), counters.active_bindings.load(),
            counters.retiring_views.load(),
            counters.retained_widgets.load(), counters.application_holds.load(),
            counters.pending_releases.load(), counters.pending_finalizations.load(),
            counters.contract_violations.load());
#else
  (void)stage;
  (void)retirement;
#endif
}

void CompleteIfFinalized(Retirement* retirement) {
  if (!retirement->own_refs_released || retirement->release_in_progress ||
      !retirement->parent_finalized || retirement->pending_finalizations != 0 ||
      retirement->violated.load()) {
    return;
  }
  RECORD_COUNTER(--counters.retiring_views);
  RECORD_COUNTER(++counters.released_views);
  g_application_release(retirement->application);
  RECORD_COUNTER(--counters.application_holds);
  g_object_unref(retirement->application);
  Trace("released", retirement);
  delete retirement;
}

void ObjectsFinalized(gpointer data) {
  auto* observers = static_cast<FinalizationObservers*>(data);
  for (const auto& observer : *observers) {
    auto* retirement = observer.retirement;
    if (g_thread_self() != retirement->gtk_thread) {
      retirement->violated.store(true);
      RECORD_COUNTER(++counters.contract_violations);
      g_critical("Retired GTK view or descendant finalized outside its GTK thread");
      continue;
    }
    if (observer.parent) retirement->parent_finalized = true;
    --retirement->pending_finalizations;
    RECORD_COUNTER(--counters.pending_finalizations);
    Trace(observer.parent ? "parent-finalized" : "descendant-finalized", retirement);
    // This may delete retirement. Do not access that state afterwards.
    CompleteIfFinalized(retirement);
  }
  delete observers;
}

void ObserveFinalization(GtkWidget* widget, Retirement* retirement, bool parent) {
  const auto quark = g_quark_from_static_string("busybooks-gtk-view-finalizations");
  auto* observers = static_cast<FinalizationObservers*>(
      g_object_get_qdata(G_OBJECT(widget), quark));
  if (observers == nullptr) {
    observers = new FinalizationObservers;
    // Ordinary weak notification also runs during forced GTK disposal. Qdata
    // survives that disposal and is cleared after the GTK/subclass finalizers.
    g_object_set_qdata_full(G_OBJECT(widget), quark, observers, ObjectsFinalized);
  }
  // A nested owned view can also appear in another owner's descendants. Append
  // observers instead of replacing qdata and prematurely notifying that owner.
  observers->push_back({retirement, parent});
  ++retirement->pending_finalizations;
  RECORD_COUNTER(++counters.pending_finalizations);
}

void RetainDescendant(GtkWidget* widget, gpointer data) {
  auto* retirement = static_cast<Retirement*>(data);
  retirement->descendants.push_back(GTK_WIDGET(g_object_ref(widget)));
  RECORD_COUNTER(++counters.retained_widgets);
  ObserveFinalization(widget, retirement, false);
  // SDK renderer first-frame/realize/size-allocate handlers contain the raw
  // FlView. A renderer idle may outlive that view after its final normal ref.
  g_signal_handlers_disconnect_by_data(widget, retirement->view);
  if (GTK_IS_CONTAINER(widget)) {
    // Include internal children as well as public container children.
    gtk_container_forall(GTK_CONTAINER(widget), RetainDescendant, retirement);
  }
}

void LastNormalReference(gpointer data, GObject*, gboolean is_last_ref);

gboolean ReleaseOnGtkThread(gpointer data) {
  auto* retirement = static_cast<Retirement*>(data);
  RECORD_COUNTER(--counters.pending_releases);
  if (g_thread_self() != retirement->gtk_thread) {
    retirement->violated.store(true);
    RECORD_COUNTER(++counters.contract_violations);
  }
  if (retirement->violated.load()) {
    // A failed diagnostic scope is not a recovery path: retain callback state
    // rather than free it while an unproven notification may still use it.
    // Any such live owner/hold or violation rejects shutdown verification.
    Trace("contract-violation", retirement);
    g_critical("GTK view retirement ownership contract was violated");
    return G_SOURCE_REMOVE;
  }

  Trace("release", retirement);
  retirement->release_in_progress = true;
  for (auto widget = retirement->descendants.rbegin();
       widget != retirement->descendants.rend(); ++widget) {
    g_object_unref(*widget);
    RECORD_COUNTER(--counters.retained_widgets);
  }
  // The toggle is the sole remaining parent reference. Removing it here makes
  // the parent's GTK finalizer run on this same GTK thread, not on raster.
  g_object_remove_toggle_ref(G_OBJECT(retirement->view), LastNormalReference,
                             retirement);
  retirement->own_refs_released = true;
  retirement->release_in_progress = false;
  Trace("owned-references-released", retirement);
  // A queued SDK renderer idle can still own a child reference. Keep the
  // application running until every actual finalizer, including that renderer,
  // has completed; this does not depend on relative GTK idle priorities.
  // Completion may delete retirement, so it is the final state operation here.
  CompleteIfFinalized(retirement);
  return G_SOURCE_REMOVE;
}

void LastNormalReference(gpointer data, GObject*, gboolean is_last_ref) {
  auto* retirement = static_cast<Retirement*>(data);
  if (!is_last_ref || retirement->queued.exchange(true)) {
    retirement->violated.store(true);
    RECORD_COUNTER(++counters.contract_violations);
    Trace("unexpected-reference-transition", retirement);
    g_critical("Destroyed GTK view acquired a new normal reference or repeated "
               "its last-reference notification");
    return;
  }
  RECORD_COUNTER(++counters.last_normal_references);
  RECORD_COUNTER(++counters.pending_releases);
  Trace("last-normal-reference", retirement);

  // This is safe only at the audited no-new-reference boundary:
  // * fl_view_dispose removes the renderable synchronously under the same
  //   mutex used by raster get_renderable (pinned SDK fl_engine.cc:175-201).
  // * GTK destroy's temporary normal reference survives this signal, recursive
  //   child destruction, and GWeakRef clearing (GLib gobject.c:1829-1851).
  // * retained descendants have no signal handlers with raw view userdata;
  //   all remaining normal view owners only release after destruction.
  // Thus there is exactly one last=true notification and no pending reverse
  // notification when the idle removes the toggle. GLib explicitly permits
  // late callbacks after toggle removal in the general case; queued is only a
  // diagnostic for a violated boundary, not protection against resurrection.
  // The idle can run before g_idle_add_full returns on a worker: this call
  // MUST be the last operation that can access retirement in this callback.
  g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, ReleaseOnGtkThread, retirement,
                  nullptr);
}

void ViewDestroyed(GtkWidget* view, gpointer data) {
  auto* application = G_APPLICATION(data);
  auto* retirement = new Retirement{
      G_APPLICATION(g_object_ref(application)), view, g_thread_self(), {}};
  RECORD_COUNTER(--counters.active_bindings);
  RECORD_COUNTER(++counters.retiring_views);
  RECORD_COUNTER(++counters.retired_views);
  ObserveFinalization(view, retirement, true);

  // A normal destroy handler runs before GtkContainer's cleanup class closure
  // recursively destroys the children. A surviving parent reference alone
  // does not preserve those children, so retain every descendant independently.
  gtk_container_forall(GTK_CONTAINER(view), RetainDescendant, retirement);
  g_application_hold(application);
  RECORD_COUNTER(++counters.application_holds);
  // GTK still owns a normal reference here. Add only this toggle, never a
  // normal parent/engine ref that would prevent the raster references draining.
  g_object_add_toggle_ref(G_OBJECT(view), LastNormalReference, retirement);
  Trace("retained", retirement);
}
}  // namespace

void BusyBooksBindGtkViewRetirement(GApplication* application, GtkWidget* view) {
  g_return_if_fail(G_IS_APPLICATION(application));
  g_return_if_fail(GTK_IS_CONTAINER(view));
  auto* binding = g_object_get_qdata(G_OBJECT(view), BindingQuark());
  if (binding != nullptr) {
    g_return_if_fail(binding == application);
    return;
  }
  // A plain marker and a destroy connection only. A qdata finalizer would run
  // after GtkWidget's finalizer and cannot enforce its GTK thread affinity.
  g_object_set_qdata(G_OBJECT(view), BindingQuark(), application);
  g_signal_connect(view, "destroy", G_CALLBACK(ViewDestroyed), application);
  RECORD_COUNTER(++counters.active_bindings);
}

void BusyBooksBindEmbeddedGtkViewCloseOwnership(GtkWidget* view) {
  g_return_if_fail(GTK_IS_WIDGET(view));
  // Measured in private-A-popup-ownership-02/close-signals.jsonl: realizing the
  // secondary SDK implicit view attaches its delete-event callback to the SAME
  // main GtkWindow. On close that callback calls g_application_quit before the
  // primary view is disposed, bypassing the primary window_manager close guard
  // and application retirement holds. Preserve every other signal/userdata.
  // Connect after SDK realization and repeat on re-realize, which reattaches it.
  g_signal_connect_after(view, "realize", G_CALLBACK(EmbeddedViewRealized), nullptr);
}

#ifdef BUSYBOOKS_VIEW_RETIREMENT_DIAGNOSTICS
BusyBooksGtkViewRetirementCounters BusyBooksGetGtkViewRetirementCounters() {
  return {counters.active_bindings.load(), counters.retiring_views.load(),
          counters.retained_widgets.load(), counters.application_holds.load(),
          counters.pending_releases.load(), counters.pending_finalizations.load(),
          counters.retired_views.load(),
          counters.released_views.load(), counters.last_normal_references.load(),
          counters.contract_violations.load()};
}
#endif
