// Minimal public-API reproducer: two independent official Flutter views in GTK.
// Link the pinned, unmodified embedder and run beside an untouched template's
// data/lib directories. No BusyBooks host, WebKit, plugins or reader state.
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

int main(int argc, char** argv) {
  g_set_prgname("busybooks-flview-shutdown-probe");
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gdk_set_program_class("BusyBooksFlViewShutdownProbe");
  G_GNUC_END_IGNORE_DEPRECATIONS
  gtk_init(&argc, &argv);
  auto* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window), "Two official Flutter views");
  gtk_window_set_default_size(GTK_WINDOW(window), 1280, 800);
  auto* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_container_add(GTK_CONTAINER(window), box);
  for (int i = 0; i < 2; ++i) {
    g_autoptr(FlDartProject) project = fl_dart_project_new();
    gdk_gl_context_clear_current();
    FlView* view = fl_view_new(project);
    gtk_box_pack_start(GTK_BOX(box), GTK_WIDGET(view), TRUE, TRUE, 0);
  }
  g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer) {
    gtk_main_quit();
  }), nullptr);
  gtk_widget_show_all(window);
  gtk_main();
  return 0;
}
