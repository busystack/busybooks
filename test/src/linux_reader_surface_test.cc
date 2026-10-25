// Real X11 pointer delivery through the same GTK surface used by ReaderHost.
// Flutter/WebKit rendering is outside this focused input-routing regression.
#include "reader_surface.h"

#include <gdk/gdkx.h>
#include <dlfcn.h>
#include <cstdio>

namespace {
int flutter_clicks = 0;
int book_clicks = 0;

gboolean Press(GtkWidget* widget, GdkEventButton* event, gpointer data) {
  // GTK also emits synthetic double/triple-press notifications according to
  // the desktop click interval. Count physical presses once on real desktops.
  if (event->type != GDK_BUTTON_PRESS) return TRUE;
  ++*static_cast<int*>(data);
  gtk_widget_grab_focus(widget);
  return TRUE;
}

void Settle() {
  for (int i = 0; i < 30; ++i) {
    while (g_main_context_iteration(nullptr, FALSE)) {}
    g_usleep(10000);
  }
}

class Pointer {
 public:
  explicit Pointer(GtkWidget* window) : window_(window) {
    display_ = gtk_widget_get_display(window_);
    g_assert_true(GDK_IS_X11_DISPLAY(display_));
    library_ = dlopen("libXtst.so.6", RTLD_NOW | RTLD_LOCAL);
    g_assert_nonnull(library_);
    motion_ = reinterpret_cast<Motion>(dlsym(library_, "XTestFakeMotionEvent"));
    button_ = reinterpret_cast<Button>(dlsym(library_, "XTestFakeButtonEvent"));
    g_assert_nonnull(motion_);
    g_assert_nonnull(button_);
  }
  ~Pointer() { dlclose(library_); }

  void Click(int x, int y) {
    int origin_x, origin_y;
    gdk_window_get_origin(gtk_widget_get_window(window_), &origin_x, &origin_y);
    auto* native = gdk_x11_display_get_xdisplay(display_);
    g_assert_true(motion_(native, DefaultScreen(native), origin_x + x,
                          origin_y + y, 0));
    g_assert_true(button_(native, 1, True, 0));
    g_assert_true(button_(native, 1, False, 0));
    gdk_display_sync(display_);
    Settle();
  }

 private:
  using Motion = int (*)(Display*, int, int, int, unsigned long);
  using Button = int (*)(Display*, unsigned int, int, unsigned long);
  GtkWidget* window_;
  GdkDisplay* display_;
  void* library_;
  Motion motion_;
  Button button_;
};

GtkWidget* InputWidget(int* clicks) {
  auto* widget = gtk_event_box_new();
  gtk_widget_set_can_focus(widget, TRUE);
  gtk_widget_add_events(widget, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK);
  g_signal_connect(widget, "button-press-event", G_CALLBACK(Press), clicks);
  return widget;
}
}  // namespace

int main(int argc, char** argv) {
  gdk_set_allowed_backends("x11");
  gtk_init(&argc, &argv);
  auto* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window), "BusyBooks native input regression");
  gtk_window_set_default_size(GTK_WINDOW(window), 800, 600);
  auto* overlay = gtk_overlay_new();
  auto* flutter = InputWidget(&flutter_clicks);
  auto* book = InputWidget(&book_clicks);
  gtk_container_add(GTK_CONTAINER(overlay), flutter);
  gtk_container_add(GTK_CONTAINER(window), overlay);
  {
    BusyBooksReaderSurface surface(GTK_OVERLAY(overlay), book);
    gtk_widget_show_all(window);
    Settle();
    Pointer pointer(window);

    // Welcome: an unused native surface must not capture the window's input.
    g_assert_false(gtk_widget_get_visible(book));
    pointer.Click(400, 300);
    g_assert_cmpint(flutter_clicks, ==, 1);
    g_assert_cmpint(book_clicks, ==, 0);

    // Routing may request visibility before Flutter supplies content bounds.
    surface.SetVisible(true);
    g_assert_false(gtk_widget_get_visible(book));
    pointer.Click(400, 300);
    g_assert_cmpint(flutter_clicks, ==, 2);

    surface.SetBounds(240, 70, 560, 530);
    Settle();
    // GTK allocates the widget at (0,0) inside a separate overlay input window.
    // Check that window's geometry: that is what the X server uses for input.
    GtkAllocation allocation;
    gdk_window_get_geometry(gtk_widget_get_parent_window(book), &allocation.x,
                            &allocation.y, &allocation.width, &allocation.height);
    g_assert_cmpint(allocation.x, ==, 240);
    g_assert_cmpint(allocation.y, ==, 70);
    g_assert_cmpint(allocation.width, ==, 560);
    g_assert_cmpint(allocation.height, ==, 530);
    pointer.Click(400, 25);  // Flutter header.
    pointer.Click(100, 300);  // Flutter sidebar.
    g_assert_cmpint(flutter_clicks, ==, 4);
    pointer.Click(500, 300);  // Native book interaction remains available.
    g_assert_cmpint(book_clicks, ==, 1);
    g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == book);

    // Opening a panel changes the native rectangle, including its input area.
    surface.SetBounds(360, 70, 440, 530);
    Settle();
    pointer.Click(300, 300);
    g_assert_cmpint(flutter_clicks, ==, 5);
    pointer.Click(500, 300);
    g_assert_cmpint(book_clicks, ==, 2);

    // Modals/Settings/Welcome hide it; recursive GTK showing cannot revive it.
    surface.SetVisible(false);
    gtk_widget_show_all(window);
    Settle();
    g_assert_false(gtk_widget_get_visible(book));
    pointer.Click(500, 300);
    g_assert_cmpint(flutter_clicks, ==, 6);
    g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == flutter);
    surface.SetVisible(true);
    Settle();
    pointer.Click(500, 300);
    g_assert_cmpint(book_clicks, ==, 3);
  }
  Settle();
  Pointer(window).Click(500, 300);
  g_assert_cmpint(flutter_clicks, ==, 7);
  gtk_widget_destroy(window);
  Settle();

  // The runner releases its native owner in the window's destroy signal,
  // before GTK disposes the overlay and removes its signal handlers.
  auto* closing_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  auto* closing_overlay = gtk_overlay_new();
  auto* closing_book = InputWidget(&book_clicks);
  gtk_container_add(GTK_CONTAINER(closing_window), closing_overlay);
  auto* closing_surface = new BusyBooksReaderSurface(
      GTK_OVERLAY(closing_overlay), closing_book);
  g_signal_connect(closing_window, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
    auto** surface = static_cast<BusyBooksReaderSurface**>(data);
    delete *surface;
    *surface = nullptr;
  }), &closing_surface);
  gtk_widget_show_all(closing_window);
  Settle();
  gtk_widget_destroy(closing_window);
  g_assert_null(closing_surface);
  Settle();
  std::puts("INPUT_RESULT welcome=1 chrome=1 book=1 resize=1 modal=1 teardown=1");
  return 0;
}
