#include "gtk_window_menu.h"

BusyBooksGtkWindowMenu::BusyBooksGtkWindowMenu(GtkWidget* source,
                                             GtkWindow* window,
                                             Request request)
    : source_(source), window_(window), request_(request) {
  g_object_add_weak_pointer(G_OBJECT(source_),
                            reinterpret_cast<gpointer*>(&source_));
  g_object_add_weak_pointer(G_OBJECT(window_),
                            reinterpret_cast<gpointer*>(&window_));
  Observe(source_);
}

BusyBooksGtkWindowMenu::~BusyBooksGtkWindowMenu() {
  if (source_ != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(source_),
                                reinterpret_cast<gpointer*>(&source_));
  }
  for (const auto& observed : observed_) {
    if (observed->widget == nullptr) continue;
    for (const auto handler : {observed->input_handler,
                               observed->add_handler}) {
      if (handler != 0 &&
          g_signal_handler_is_connected(observed->widget, handler)) {
        g_signal_handler_disconnect(observed->widget, handler);
      }
    }
    g_object_remove_weak_pointer(
        G_OBJECT(observed->widget),
        reinterpret_cast<gpointer*>(&observed->widget));
  }
  if (window_ != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(window_),
                                reinterpret_cast<gpointer*>(&window_));
  }
  g_clear_pointer(&trigger_, gdk_event_free);
}

void BusyBooksGtkWindowMenu::Observe(GtkWidget* widget) {
  for (const auto& observed : observed_) {
    if (observed->widget == widget) return;
  }
  auto observed = std::make_unique<ObservedWidget>();
  observed->widget = widget;
  g_object_add_weak_pointer(G_OBJECT(widget),
                           reinterpret_cast<gpointer*>(&observed->widget));
  // A child can consume the button-specific signal before it bubbles to the
  // root. Observe the public GTK hierarchy, without assuming a FlView layout.
  // Generic event runs before button handlers and must propagate unchanged.
  observed->input_handler =
      g_signal_connect(widget, "event", G_CALLBACK(Input), this);
  observed->add_handler = GTK_IS_CONTAINER(widget)
      ? g_signal_connect(widget, "add", G_CALLBACK(ChildAdded), this)
      : 0;
  observed_.push_back(std::move(observed));
  if (GTK_IS_CONTAINER(widget)) {
    gtk_container_forall(GTK_CONTAINER(widget), VisitChild, this);
  }
}

void BusyBooksGtkWindowMenu::ChildAdded(GtkContainer*, GtkWidget* child,
                                       gpointer data) {
  static_cast<BusyBooksGtkWindowMenu*>(data)->Observe(child);
}

void BusyBooksGtkWindowMenu::VisitChild(GtkWidget* child, gpointer data) {
  static_cast<BusyBooksGtkWindowMenu*>(data)->Observe(child);
}

gboolean BusyBooksGtkWindowMenu::Input(GtkWidget* widget, GdkEvent* event,
                                      gpointer data) {
  auto* self = static_cast<BusyBooksGtkWindowMenu*>(data);
  if (self->source_ == nullptr ||
      (widget != self->source_ &&
       !gtk_widget_is_ancestor(widget, self->source_))) return FALSE;
  if (event->type == GDK_BUTTON_PRESS || event->type == GDK_BUTTON_RELEASE) {
    g_clear_pointer(&self->trigger_, gdk_event_free);
    // event_copy retains the event's real device, window and backend input
    // identity. The original event and its fields remain owned by GTK.
    if (gdk_event_get_device(event) != nullptr) {
      self->trigger_ = gdk_event_copy(event);
    }
  } else if (event->type == GDK_KEY_PRESS ||
             (widget == self->source_ && event->type == GDK_FOCUS_CHANGE &&
              !event->focus_change.in)) {
    g_clear_pointer(&self->trigger_, gdk_event_free);
  }
  return FALSE;
}

bool BusyBooksGtkWindowMenu::Show() {
  g_autoptr(GdkEvent) trigger = trigger_;
  trigger_ = nullptr;
  if (trigger == nullptr || source_ == nullptr || window_ == nullptr ||
      !gtk_widget_get_mapped(source_) ||
      !gtk_widget_get_mapped(GTK_WIDGET(window_))) {
    return false;
  }
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(window_));
  if (window == nullptr || gdk_window_is_destroyed(window)) return false;
  return request_(window, trigger);
}
