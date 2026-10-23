#include "reader_surface.h"

BusyBooksReaderSurface::BusyBooksReaderSurface(GtkOverlay* overlay,
                                             GtkWidget* content)
    : overlay_(overlay), content_(content) {
  g_object_ref(overlay_);
  // A recursive show_all from a window/plugin must not expose an unused book
  // surface on Welcome or above a Flutter modal.
  gtk_widget_set_no_show_all(content_, TRUE);
  gtk_widget_hide(content_);
  position_handler_ = g_signal_connect(
      overlay_, "get-child-position", G_CALLBACK(Position), this);
  gtk_overlay_add_overlay(overlay_, content_);
  g_object_ref(content_);
}

BusyBooksReaderSurface::~BusyBooksReaderSurface() {
  g_signal_handler_disconnect(overlay_, position_handler_);
  gtk_widget_destroy(content_);
  g_object_unref(content_);
  g_object_unref(overlay_);
}

void BusyBooksReaderSurface::SetBounds(int x, int y, int width, int height) {
  has_bounds_ = x >= 0 && y >= 0 && width > 0 && height > 0;
  if (has_bounds_) bounds_ = {x, y, width, height};
  gtk_widget_queue_resize(GTK_WIDGET(overlay_));
  UpdateVisibility();
}

void BusyBooksReaderSurface::SetVisible(bool visible) {
  visible_ = visible;
  UpdateVisibility();
}

void BusyBooksReaderSurface::UpdateVisibility() {
  gtk_widget_set_visible(content_, visible_ && has_bounds_);
}

gboolean BusyBooksReaderSurface::Position(GtkOverlay*, GtkWidget* child,
                                         GdkRectangle* allocation,
                                         gpointer data) {
  const auto* self = static_cast<BusyBooksReaderSurface*>(data);
  if (child != self->content_) return FALSE;
  *allocation = self->bounds_;
  return TRUE;
}
