#ifndef BUSYBOOKS_READER_SURFACE_H_
#define BUSYBOOKS_READER_SURFACE_H_

#include <gtk/gtk.h>

// Only the book rectangle owns a native input window. Flutter remains the
// overlay's main child and receives input everywhere else.
class BusyBooksReaderSurface {
 public:
  BusyBooksReaderSurface(GtkOverlay* overlay, GtkWidget* content);
  ~BusyBooksReaderSurface();
  BusyBooksReaderSurface(const BusyBooksReaderSurface&) = delete;
  BusyBooksReaderSurface& operator=(const BusyBooksReaderSurface&) = delete;

  void SetBounds(int x, int y, int width, int height);
  void SetVisible(bool visible);

 private:
  static gboolean Position(GtkOverlay*, GtkWidget*, GdkRectangle*, gpointer);
  void UpdateVisibility();

  GtkOverlay* overlay_;
  GtkWidget* content_;
  gulong position_handler_;
  GdkRectangle bounds_{0, 0, 1, 1};
  bool has_bounds_ = false;
  bool visible_ = false;
};

#endif
