#include "gtk_view_retirement.h"

#include <cstdio>

namespace {
struct Lifetime {
  GThread* gtk_thread = g_thread_self();
  bool parent_finalized = false;
  bool child_finalized = false;
  bool renderer_finalized = false;
  bool frame_active = false;
  bool require_finished_frame = true;
  guint parent_callbacks = 0;
  guint unrelated_callbacks = 0;
};

struct TestView { GtkBox parent; Lifetime* lifetime; };
struct TestViewClass { GtkBoxClass parent; };
G_DEFINE_TYPE(TestView, test_view, GTK_TYPE_BOX)

void test_view_finalize(GObject* object) {
  auto* lifetime = reinterpret_cast<TestView*>(object)->lifetime;
  g_assert_true(g_thread_self() == lifetime->gtk_thread);
  lifetime->parent_finalized = true;
  G_OBJECT_CLASS(test_view_parent_class)->finalize(object);
}
void test_view_class_init(TestViewClass* klass) {
  G_OBJECT_CLASS(klass)->finalize = test_view_finalize;
}
void test_view_init(TestView*) {}

struct TestChild { GtkEventBox parent; Lifetime* lifetime; };
struct TestChildClass { GtkEventBoxClass parent; };
G_DEFINE_TYPE(TestChild, test_child, GTK_TYPE_EVENT_BOX)

void test_child_finalize(GObject* object) {
  auto* lifetime = reinterpret_cast<TestChild*>(object)->lifetime;
  g_assert_true(g_thread_self() == lifetime->gtk_thread);
  lifetime->child_finalized = true;
  G_OBJECT_CLASS(test_child_parent_class)->finalize(object);
}
void test_child_class_init(TestChildClass* klass) {
  G_OBJECT_CLASS(klass)->finalize = test_child_finalize;
}
void test_child_init(TestChild*) {}

struct TestRenderer { GtkDrawingArea parent; Lifetime* lifetime; };
struct TestRendererClass { GtkDrawingAreaClass parent; };
G_DEFINE_TYPE(TestRenderer, test_renderer, GTK_TYPE_DRAWING_AREA)
guint frame_signal;

void test_renderer_finalize(GObject* object) {
  auto* lifetime = reinterpret_cast<TestRenderer*>(object)->lifetime;
  g_assert_true(g_thread_self() == lifetime->gtk_thread);
  if (lifetime->require_finished_frame) g_assert_false(lifetime->frame_active);
  lifetime->renderer_finalized = true;
  G_OBJECT_CLASS(test_renderer_parent_class)->finalize(object);
}
void test_renderer_class_init(TestRendererClass* klass) {
  G_OBJECT_CLASS(klass)->finalize = test_renderer_finalize;
  frame_signal = g_signal_new("test-frame", G_TYPE_FROM_CLASS(klass),
      G_SIGNAL_RUN_LAST, 0, nullptr, nullptr, nullptr, G_TYPE_NONE, 0);
}
void test_renderer_init(TestRenderer*) {}

void Settle() {
  while (g_main_context_iteration(nullptr, FALSE)) {}
}

void AssertEmpty() {
  const auto counters = BusyBooksGetGtkViewRetirementCounters();
  g_assert_cmpuint(counters.active_bindings, ==, 0);
  g_assert_cmpuint(counters.retiring_views, ==, 0);
  g_assert_cmpuint(counters.retained_widgets, ==, 0);
  g_assert_cmpuint(counters.application_holds, ==, 0);
  g_assert_cmpuint(counters.pending_releases, ==, 0);
  g_assert_cmpuint(counters.pending_finalizations, ==, 0);
  g_assert_cmpuint(counters.contract_violations, ==, 0);
}

struct View {
  Lifetime lifetime;
  GtkWidget* widget;
  GtkWidget* child;
  GtkWidget* renderer;
  GWeakRef weak;

  View(GApplication* application, bool bind) {
    widget = GTK_WIDGET(g_object_new(test_view_get_type(), nullptr));
    g_object_ref_sink(widget);
    reinterpret_cast<TestView*>(widget)->lifetime = &lifetime;
    child = GTK_WIDGET(g_object_new(test_child_get_type(), nullptr));
    reinterpret_cast<TestChild*>(child)->lifetime = &lifetime;
    renderer = GTK_WIDGET(g_object_new(test_renderer_get_type(), nullptr));
    reinterpret_cast<TestRenderer*>(renderer)->lifetime = &lifetime;
    gtk_container_add(GTK_CONTAINER(child), renderer);
    gtk_container_add(GTK_CONTAINER(widget), child);
    g_weak_ref_init(&weak, G_OBJECT(widget));
    // Both destroy-time and late child signals must lose their raw view data.
    g_signal_connect(renderer, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
      ++reinterpret_cast<TestView*>(data)->lifetime->parent_callbacks;
    }), widget);
    g_signal_connect(renderer, "test-frame", G_CALLBACK(+[](GtkWidget*, gpointer data) {
      ++reinterpret_cast<TestView*>(data)->lifetime->parent_callbacks;
    }), widget);
    g_signal_connect(renderer, "test-frame", G_CALLBACK(+[](GtkWidget*, gpointer data) {
      ++static_cast<Lifetime*>(data)->unrelated_callbacks;
    }), &lifetime);
    g_signal_connect(renderer, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
      ++static_cast<Lifetime*>(data)->unrelated_callbacks;
    }), &lifetime);
    if (bind) {
      const auto view_refs = G_OBJECT(widget)->ref_count;
      const auto child_refs = G_OBJECT(child)->ref_count;
      const auto renderer_refs = G_OBJECT(renderer)->ref_count;
      const auto app_refs = G_OBJECT(application)->ref_count;
      BusyBooksBindGtkViewRetirement(application, widget);
      BusyBooksBindGtkViewRetirement(application, widget);
      g_assert_cmpuint(G_OBJECT(widget)->ref_count, ==, view_refs);
      g_assert_cmpuint(G_OBJECT(child)->ref_count, ==, child_refs);
      g_assert_cmpuint(G_OBJECT(renderer)->ref_count, ==, renderer_refs);
      g_assert_cmpuint(G_OBJECT(application)->ref_count, ==, app_refs);
    }
  }

  void Destroy() {
    gtk_widget_destroy(widget);
    // GTK has cleared weak acquisition before the temporary normal ref drains.
    g_assert_null(g_weak_ref_get(&weak));
    g_object_unref(widget);
  }
  ~View() { g_weak_ref_clear(&weak); }
};

// A real worker acquires the parent before destroy, models the SDK's existing
// raster owner, and later releases it. It never queries GTK widget state.
class Frame {
 public:
  Frame(View& view, bool late_renderer_ref, bool hand_back_parent = false)
      : parent_(view.widget), renderer_(late_renderer_ref ? view.renderer : nullptr),
        hand_back_parent_(hand_back_parent) {
    view.lifetime.frame_active = true;
    g_mutex_init(&mutex_);
    g_cond_init(&condition_);
    thread_ = g_thread_new("raster-reference", Run, this);
    g_mutex_lock(&mutex_);
    while (!acquired_) g_cond_wait(&condition_, &mutex_);
    g_mutex_unlock(&mutex_);
  }

  gpointer Complete() {
    g_mutex_lock(&mutex_);
    complete_ = true;
    g_cond_signal(&condition_);
    g_mutex_unlock(&mutex_);
    auto* result = g_thread_join(thread_);
    thread_ = nullptr;
    return result;
  }

  ~Frame() {
    g_assert_null(thread_);
    g_cond_clear(&condition_);
    g_mutex_clear(&mutex_);
  }

 private:
  static gpointer Run(gpointer data) {
    auto* self = static_cast<Frame*>(data);
    auto* parent = g_object_ref(self->parent_);
    g_mutex_lock(&self->mutex_);
    self->acquired_ = true;
    g_cond_signal(&self->condition_);
    while (!self->complete_) g_cond_wait(&self->condition_, &self->mutex_);
    g_mutex_unlock(&self->mutex_);
    if (self->hand_back_parent_) return parent;
    // Model the renderer's late queued-redraw reference, taken after rendering
    // but before the enclosing SDK presentation drops its parent reference.
    auto* renderer = self->renderer_ ? g_object_ref(self->renderer_) : nullptr;
    g_object_unref(parent);
    return renderer;
  }

  GtkWidget* parent_;
  GtkWidget* renderer_;
  bool hand_back_parent_;
  GMutex mutex_;
  GCond condition_;
  bool acquired_ = false;
  bool complete_ = false;
  GThread* thread_;
};

void TestEmbeddedCloseOwnership() {
  auto* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_object_ref_sink(window);
  auto* content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  auto* primary = gtk_drawing_area_new();
  auto* embedded = gtk_drawing_area_new();
  gtk_container_add(GTK_CONTAINER(window), content);
  gtk_container_add(GTK_CONTAINER(content), primary);
  gtk_container_add(GTK_CONTAINER(content), embedded);
  guint primary_calls = 0, embedded_calls = 0, guard_calls = 0;
  g_object_set_data(G_OBJECT(primary), "close-test-counter", &primary_calls);
  g_object_set_data(G_OBJECT(embedded), "close-test-counter", &embedded_calls);
  const auto count_view = +[](GtkWidget*, GdkEvent*, gpointer view) -> gboolean {
    ++*static_cast<guint*>(g_object_get_data(G_OBJECT(view), "close-test-counter"));
    return FALSE;
  };
  const auto primary_handler = g_signal_connect(window, "delete-event",
      G_CALLBACK(count_view), primary);
  const auto guard_handler = g_signal_connect(window, "delete-event",
      G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer data) -> gboolean {
        ++*static_cast<guint*>(data);
        return FALSE;
      }), &guard_calls);
  // Same secondary userdata on a different signal must also survive.
  const auto other_signal = g_signal_connect(window, "notify::title",
      G_CALLBACK(+[](GObject*, GParamSpec*, gpointer) {}), embedded);
  struct Realization {
    GtkWidget* window;
    GCallback callback;
    gulong handler = 0;
    guint count = 0;
  } realization{window, G_CALLBACK(count_view)};
  g_signal_connect(embedded, "realize", G_CALLBACK(+[](GtkWidget* view, gpointer data) {
    auto* state = static_cast<Realization*>(data);
    state->handler = g_signal_connect(state->window, "delete-event", state->callback, view);
    ++state->count;
  }), &realization);
  BusyBooksBindEmbeddedGtkViewCloseOwnership(embedded);
  gtk_widget_realize(window);
  for (guint iteration = 1; iteration <= 2; ++iteration) {
    gtk_widget_realize(embedded);
    g_assert_false(gtk_widget_get_mapped(window));
    g_assert_cmpuint(realization.count, ==, iteration);
    g_assert_false(g_signal_handler_is_connected(window, realization.handler));
    g_assert_true(g_signal_handler_is_connected(window, primary_handler));
    g_assert_true(g_signal_handler_is_connected(window, guard_handler));
    g_assert_true(g_signal_handler_is_connected(window, other_signal));
    gboolean handled = FALSE;
    g_signal_emit_by_name(window, "delete-event", nullptr, &handled);
    g_assert_false(handled);
    g_assert_cmpuint(primary_calls, ==, iteration);
    g_assert_cmpuint(guard_calls, ==, iteration);
    g_assert_cmpuint(embedded_calls, ==, 0);
    gtk_widget_unrealize(embedded);
  }
  gtk_widget_destroy(window);
  g_object_unref(window);
  Settle();
}
}  // namespace

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  TestEmbeddedCloseOwnership();
  auto* application = g_application_new("io.busystack.busybooks.retirement-test",
                                       G_APPLICATION_NON_UNIQUE);
  const auto app_refs = G_OBJECT(application)->ref_count;
  {
    // Negative control: a worker-held parent does not keep GTK children alive.
    View unowned(application, false);
    unowned.lifetime.require_finished_frame = false;
    Frame frame(unowned, false, true);
    unowned.Destroy();
    g_assert_false(unowned.lifetime.parent_finalized);
    g_assert_true(unowned.lifetime.child_finalized);
    g_assert_true(unowned.lifetime.renderer_finalized);
    g_assert_true(unowned.lifetime.frame_active);
    // Return this negative control's parent to GTK for final release; there is
    // no reason to execute a known off-thread GtkWidget finalizer in the test.
    auto* parent = frame.Complete();
    unowned.lifetime.frame_active = false;
    g_object_unref(parent);
    g_assert_true(unowned.lifetime.parent_finalized);
  }
  AssertEmpty();
  {
    View first(application, true), second(application, true);
    g_assert_cmpuint(BusyBooksGetGtkViewRetirementCounters().active_bindings, ==, 2);
    Frame first_frame(first, true), second_frame(second, false);
    first.Destroy();
    second.Destroy();
    auto counters = BusyBooksGetGtkViewRetirementCounters();
    g_assert_cmpuint(counters.retiring_views, ==, 2);
    g_assert_cmpuint(counters.retained_widgets, ==, 4);
    g_assert_cmpuint(counters.application_holds, ==, 2);
    g_assert_cmpuint(counters.pending_releases, ==, 0);
    g_assert_cmpuint(first.lifetime.parent_callbacks, ==, 0);
    g_assert_cmpuint(second.lifetime.parent_callbacks, ==, 0);
    g_assert_cmpuint(first.lifetime.unrelated_callbacks, ==, 1);
    g_assert_cmpuint(second.lifetime.unrelated_callbacks, ==, 1);
    g_signal_emit(first.renderer, frame_signal, 0);
    g_assert_cmpuint(first.lifetime.parent_callbacks, ==, 0);
    // GTK disconnects ordinary child handlers during destroy too. Explicitly
    // reconnect an unrelated late callback to show the retained child is inert
    // but allocated and safe for the renderer's queued main-thread completion.
    g_signal_connect(first.renderer, "test-frame", G_CALLBACK(+[](GtkWidget*, gpointer data) {
      ++static_cast<Lifetime*>(data)->unrelated_callbacks;
    }), &first.lifetime);
    g_signal_emit(first.renderer, frame_signal, 0);
    g_assert_cmpuint(first.lifetime.unrelated_callbacks, ==, 2);
    Settle();
    g_assert_false(first.lifetime.child_finalized);
    g_assert_false(first.lifetime.renderer_finalized);
    g_assert_false(second.lifetime.child_finalized);
    auto* redraw = first_frame.Complete();
    first.lifetime.frame_active = false;
    g_assert_nonnull(redraw);
    g_assert_false(first.lifetime.parent_finalized);
    g_assert_false(first.lifetime.renderer_finalized);
    Settle();
    g_assert_true(first.lifetime.parent_finalized);
    g_assert_true(first.lifetime.child_finalized);
    g_assert_false(first.lifetime.renderer_finalized);
    g_assert_false(second.lifetime.parent_finalized);
    counters = BusyBooksGetGtkViewRetirementCounters();
    g_assert_cmpuint(counters.retiring_views, ==, 2);
    g_assert_cmpuint(counters.application_holds, ==, 2);
    g_assert_cmpuint(counters.pending_finalizations, ==, 4);
    // The SDK's redraw reference can outlive our parent cleanup, regardless of
    // idle ordering. Its actual finalizer must be the event releasing our hold.
    struct RedrawCompletion {
      View* view;
      gpointer renderer;
      guint holds_before;
      bool completed = false;
    } completion{&first, redraw, counters.application_holds};
    g_idle_add_full(G_PRIORITY_LOW, +[](gpointer data) -> gboolean {
      auto* completion = static_cast<RedrawCompletion*>(data);
      g_assert_true(completion->view->lifetime.parent_finalized);
      g_assert_false(completion->view->lifetime.renderer_finalized);
      g_assert_cmpuint(BusyBooksGetGtkViewRetirementCounters().application_holds,
                       ==, completion->holds_before);
      g_object_unref(completion->renderer);
      g_assert_true(completion->view->lifetime.renderer_finalized);
      g_assert_cmpuint(BusyBooksGetGtkViewRetirementCounters().application_holds,
                       ==, completion->holds_before - 1);
      completion->completed = true;
      return G_SOURCE_REMOVE;
    }, &completion, nullptr);
    Settle();
    g_assert_true(completion.completed);
    g_assert_true(first.lifetime.renderer_finalized);
    g_assert_null(second_frame.Complete());
    second.lifetime.frame_active = false;
    Settle();
    g_assert_true(second.lifetime.parent_finalized);
    g_assert_true(second.lifetime.child_finalized);
    g_assert_true(second.lifetime.renderer_finalized);
  }
  AssertEmpty();
  {
    View synchronous(application, true);
    synchronous.Destroy();
    g_assert_false(synchronous.lifetime.parent_finalized);
    g_assert_false(synchronous.lifetime.renderer_finalized);
    Settle();
    g_assert_true(synchronous.lifetime.parent_finalized);
    g_assert_true(synchronous.lifetime.child_finalized);
    g_assert_true(synchronous.lifetime.renderer_finalized);
  }
  AssertEmpty();
  {
    // Nested retirement owners share child finalization observations. Neither
    // may replace the other's qdata notifier or keep the other's children alive.
    View nested(application, true);
    BusyBooksBindGtkViewRetirement(application, nested.child);
    Frame frame(nested, false);
    nested.Destroy();
    g_assert_cmpuint(BusyBooksGetGtkViewRetirementCounters().application_holds, ==, 2);
    g_assert_null(frame.Complete());
    nested.lifetime.frame_active = false;
    Settle();
    g_assert_true(nested.lifetime.parent_finalized);
    g_assert_true(nested.lifetime.child_finalized);
    g_assert_true(nested.lifetime.renderer_finalized);
  }
  AssertEmpty();
  g_assert_cmpuint(G_OBJECT(application)->ref_count, ==, app_refs);
  const auto counters = BusyBooksGetGtkViewRetirementCounters();
  g_assert_cmpuint(counters.retired_views, ==, 5);
  g_assert_cmpuint(counters.released_views, ==, 5);
  g_assert_cmpuint(counters.last_normal_references, ==, 5);
  std::printf("VIEW_RETIREMENT_RESULT negative_control=1 worker_reference=1 "
      "nested_descendants=1 late_renderer_reference=1 weak_refs_cleared=1 "
      "independent_views=1 main_thread_finalizers=1 synchronous_destroy=1 "
      "embedded_close_scoped=1 embedded_close_rerealize=1 "
      "actual_finalize_barrier=1 lower_priority_redraw=1 shared_observers=1 "
      "raw_parent_callbacks=0 retired=%u released=%u last_normal=%u "
      "active=%u retiring=%u retained=%u holds=%u pending=%u finalizers=%u violations=%u\n",
      counters.retired_views, counters.released_views, counters.last_normal_references,
      counters.active_bindings, counters.retiring_views, counters.retained_widgets,
      counters.application_holds, counters.pending_releases,
      counters.pending_finalizations, counters.contract_violations);
  g_object_unref(application);
}
