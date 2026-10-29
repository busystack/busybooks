// Real X11 pointer delivery through the same GTK surface used by ReaderHost.
// Flutter/WebKit rendering is outside this focused input-routing regression.
#include "reader_surface.h"
#include "gtk_window_menu.h"

#include <gdk/gdkx.h>
#include <dlfcn.h>
#include <cstdio>

namespace {
int flutter_clicks = 0;
int book_clicks = 0;
int window_menu_requests = 0;

gboolean RequestWindowMenu(GdkWindow* window, GdkEvent* trigger) {
  g_assert_true(GDK_IS_WINDOW(window));
  g_assert_false(gdk_window_is_destroyed(window));
  g_assert_true(GDK_IS_WINDOW(gdk_event_get_window(trigger)));
  g_assert_true(GDK_IS_DEVICE(gdk_event_get_device(trigger)));
  g_assert_cmpint(trigger->type, ==, GDK_BUTTON_RELEASE);
  guint button = 0;
  g_assert_true(gdk_event_get_button(trigger, &button));
  g_assert_cmpuint(button, ==, 3);
  ++window_menu_requests;
  return TRUE;
}

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
    // Own the XTest connection so its extension state is released before the
    // dynamically loaded library. GTK keeps its separate display connection.
    native_display_ = XOpenDisplay(DisplayString(gdk_x11_display_get_xdisplay(display_)));
    g_assert_nonnull(native_display_);
  }
  ~Pointer() {
    XCloseDisplay(native_display_);
    dlclose(library_);
  }

  void Click(int x, int y, unsigned int button = 1) {
    int origin_x, origin_y;
    gdk_window_get_origin(gtk_widget_get_window(window_), &origin_x, &origin_y);
    auto* native = native_display_;
    g_assert_true(motion_(native, DefaultScreen(native), origin_x + x,
                          origin_y + y, 0));
    g_assert_true(button_(native, button, True, 0));
    g_assert_true(button_(native, button, False, 0));
    XSync(native, False);
    gdk_display_sync(display_);
    Settle();
  }

 private:
  using Motion = int (*)(Display*, int, int, int, unsigned long);
  using Button = int (*)(Display*, unsigned int, int, unsigned long);
  GtkWidget* window_;
  GdkDisplay* display_;
  Display* native_display_;
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

  // The application channel runs after GTK releases the original pointer
  // event. Its owned copy keeps the actual window/device valid, and does not
  // consume the pointer event needed by Flutter's titlebar gesture.
  auto* menu_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  int menu_clicks = 0, menu_parent_clicks = 0;
  auto* menu_content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  auto* menu_input = InputWidget(&menu_clicks);
  gtk_box_pack_start(GTK_BOX(menu_content), menu_input, TRUE, TRUE, 0);
  g_signal_connect(menu_content, "button-press-event", G_CALLBACK(Press),
                   &menu_parent_clicks);
  gtk_container_add(GTK_CONTAINER(menu_window), menu_content);
  gtk_window_set_default_size(GTK_WINDOW(menu_window), 300, 120);
  {
    BusyBooksGtkWindowMenu menu(menu_content, GTK_WINDOW(menu_window),
                                RequestWindowMenu);
    gtk_widget_show_all(menu_window);
    Settle();
    g_assert_false(menu.Show());
    Pointer pointer(menu_window);
    for (int index = 0; index < 4; ++index) {
      if (index == 2) {
        // A supported child can be created after the application host. Its
        // consuming handler still must not hide the real event from capture.
        gtk_widget_destroy(menu_input);
        menu_input = InputWidget(&menu_clicks);
        gtk_box_pack_start(GTK_BOX(menu_content), menu_input, TRUE, TRUE, 0);
        gtk_widget_show_all(menu_content);
        Settle();
      }
      pointer.Click(100, 50, 3);
      g_assert_cmpint(menu_clicks, ==, index + 1);
      g_assert_cmpint(menu_parent_clicks, ==, 0);
      g_assert_true(menu.Show());
      g_assert_false(menu.Show());
      g_assert_cmpint(window_menu_requests, ==, index + 1);
      g_assert_false(gdk_window_is_destroyed(gtk_widget_get_window(menu_window)));
    }
    pointer.Click(100, 50, 3);
    gtk_widget_hide(menu_window);
    g_assert_false(menu.Show());
    g_assert_cmpint(window_menu_requests, ==, 4);
    gtk_widget_destroy(menu_window);
    g_assert_false(menu.Show());
  }
  Settle();
  std::puts("WINDOW_MENU_RESULT real_event=1 consumed_child=1 added_child=1 propagated=1 one_shot=1 hidden=1 teardown=1");
  std::puts("INPUT_RESULT welcome=1 chrome=1 book=1 resize=1 modal=1 teardown=1");
  std::fflush(stdout);
  return 0;
}
