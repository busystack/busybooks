#ifndef BUSYBOOKS_GTK_WINDOW_MENU_H_
#define BUSYBOOKS_GTK_WINDOW_MENU_H_

#include <gtk/gtk.h>
#include <memory>
#include <vector>

// A Flutter gesture arrives after GTK has released its original input event.
// Keep one owned event for the application channel's window-menu request.
class BusyBooksGtkWindowMenu {
 public:
  using Request = gboolean (*)(GdkWindow*, GdkEvent*);

  BusyBooksGtkWindowMenu(GtkWidget* source, GtkWindow* window,
                        Request request = gdk_window_show_window_menu);
  ~BusyBooksGtkWindowMenu();
  BusyBooksGtkWindowMenu(const BusyBooksGtkWindowMenu&) = delete;
  BusyBooksGtkWindowMenu& operator=(const BusyBooksGtkWindowMenu&) = delete;

  // A compositor may decline the request. Never synthesize a dependency event
  // or fall back to Yaru's window-menu implementation.
  bool Show();

 private:
  struct ObservedWidget {
    GtkWidget* widget;
    gulong input_handler;
    gulong add_handler;
  };

  void Observe(GtkWidget* widget);
  static gboolean Input(GtkWidget*, GdkEvent*, gpointer);
  static void ChildAdded(GtkContainer*, GtkWidget*, gpointer);
  static void VisitChild(GtkWidget*, gpointer);

  GtkWidget* source_;
  GtkWindow* window_;
  Request request_;
  std::vector<std::unique_ptr<ObservedWidget>> observed_;
  GdkEvent* trigger_ = nullptr;
};

#endif
