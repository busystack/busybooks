// Adapted from BusyMark; unrelated authoring integrations removed for BusyBooks.
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <handy.h>
#include <pango/pango.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

#include "flutter/generated_plugin_registrant.h"
#include "gtk_accent_host.h"
#include "gtk_view_retirement.h"
#include "linux_chrome_host.h"
#include "reader_host.h"
#include "native_menu_host.h"






constexpr char kApplicationDisplayName[] = "BusyBooks";
constexpr char kAssetInputChannel[] = "com.busybooks.app/asset_input";
constexpr char kLegacyYaruWindowShadowCompatibilityCss[] =
    "window#busybooks-window:not(.solid-csd):not(.maximized):"
    "not(.fullscreen):not(.tiled):not(.tiled-top):not(.tiled-right):"
    "not(.tiled-bottom):not(.tiled-left) > decoration {"
    "box-shadow: 0 3px 9px 1px rgba(0,0,0,0.5);"
    "}"
    "window#busybooks-window:not(.solid-csd):not(.maximized):"
    "not(.fullscreen):not(.tiled):not(.tiled-top):not(.tiled-right):"
    "not(.tiled-bottom):not(.tiled-left) > decoration:backdrop {"
    "box-shadow: 0 3px 9px 1px transparent,"
    "0 2px 6px 2px rgba(0,0,0,0.2);"
    "}"
    "window#busybooks-window.tiled:not(.solid-csd):not(.maximized):"
    "not(.fullscreen) > decoration,"
    "window#busybooks-window.tiled-top:not(.solid-csd):not(.maximized):"
    "not(.fullscreen) > decoration,"
    "window#busybooks-window.tiled-right:not(.solid-csd):not(.maximized):"
    "not(.fullscreen) > decoration,"
    "window#busybooks-window.tiled-bottom:not(.solid-csd):not(.maximized):"
    "not(.fullscreen) > decoration,"
    "window#busybooks-window.tiled-left:not(.solid-csd):not(.maximized):"
    "not(.fullscreen) > decoration {"
    "box-shadow: 0 0 0 20px transparent;"
    "}";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  BusyBooksGtkAccentHost* gtk_accent_host;
  BusyBooksLinuxChromeHost* chrome_host;
  FlMethodChannel* native_menu_channel;

  FlMethodChannel* asset_input_channel;
  GPtrArray* pending_paths;
  gboolean input_ready;




  BusyBooksReaderHost* reader_host;
  GtkCssProvider* native_surface_css_provider;
  GtkWindow* main_window;
  GtkWidget* flutter_view;
  GtkWidget* flutter_overlay;
};
G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static GdkPixbuf* load_application_icon_at_size(gint size) {
  g_autofree gchar* executable_path =
      g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path == nullptr) {
    return nullptr;
  }

  g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
  g_autofree gchar* icon_path =
      g_build_filename(executable_dir, "data", "flutter_assets", "assets",
                       "branding", "busybooks_logo.svg", nullptr);

  g_autoptr(GError) error = nullptr;
  GdkPixbuf* icon =
      gdk_pixbuf_new_from_file_at_size(icon_path, size, size, &error);
  if (icon == nullptr) {
    const gchar* message = error != nullptr ? error->message : "unknown error";
    g_warning("Failed to load application icon: %s", message);
  }
  return icon;
}

static GdkPixbuf* load_application_icon() {
  return load_application_icon_at_size(256);
}

static gboolean gtk_theme_exists_in_data_dir(const gchar* data_dir,
                                             const gchar* theme_name) {
  if (data_dir == nullptr || theme_name == nullptr || theme_name[0] == '\0') {
    return FALSE;
  }
  g_autofree gchar* css_path =
      g_build_filename(data_dir, "themes", theme_name, "gtk-3.0", "gtk.css",
                       nullptr);
  return g_file_test(css_path, G_FILE_TEST_IS_REGULAR);
}

static gboolean gtk_theme_exists(const gchar* theme_name) {
  if (gtk_theme_exists_in_data_dir(g_get_user_data_dir(), theme_name)) {
    return TRUE;
  }
  const gchar* const* data_dirs = g_get_system_data_dirs();
  for (gint i = 0; data_dirs != nullptr && data_dirs[i] != nullptr; ++i) {
    if (gtk_theme_exists_in_data_dir(data_dirs[i], theme_name)) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean icon_theme_exists_in_data_dir(const gchar* data_dir,
                                              const gchar* theme_name) {
  if (data_dir == nullptr || theme_name == nullptr || theme_name[0] == '\0') {
    return FALSE;
  }
  g_autofree gchar* index_path =
      g_build_filename(data_dir, "icons", theme_name, "index.theme", nullptr);
  return g_file_test(index_path, G_FILE_TEST_IS_REGULAR);
}

static gboolean icon_theme_exists(const gchar* theme_name) {
  if (icon_theme_exists_in_data_dir(g_get_user_data_dir(), theme_name)) {
    return TRUE;
  }
  const gchar* const* data_dirs = g_get_system_data_dirs();
  for (gint i = 0; data_dirs != nullptr && data_dirs[i] != nullptr; ++i) {
    if (icon_theme_exists_in_data_dir(data_dirs[i], theme_name)) {
      return TRUE;
    }
  }
  return FALSE;
}

static const gchar* available_gtk_theme_fallback(gboolean prefer_dark) {
  const gchar* primary = prefer_dark ? "Yaru-dark" : "Yaru";
  if (gtk_theme_exists(primary)) {
    return primary;
  }
  const gchar* secondary = prefer_dark ? "Adwaita-dark" : "Adwaita";
  return gtk_theme_exists(secondary) ? secondary : nullptr;
}

static const gchar* available_icon_theme_fallback(gboolean prefer_dark) {
  const gchar* primary = prefer_dark ? "Yaru-dark" : "Yaru";
  if (icon_theme_exists(primary)) {
    return primary;
  }
  return icon_theme_exists("Adwaita") ? "Adwaita" : nullptr;
}

static void set_gtk_theme_preference(gboolean prefer_dark) {
  GtkSettings* settings = gtk_settings_get_default();
  if (settings != nullptr) {
    g_object_set(settings, "gtk-application-prefer-dark-theme", prefer_dark,
                 nullptr);

    g_autofree gchar* theme_name = nullptr;
    g_object_get(settings, "gtk-theme-name", &theme_name, nullptr);
    const gchar* fallback = available_gtk_theme_fallback(prefer_dark);
    if (fallback != nullptr && !gtk_theme_exists(theme_name)) {
      g_object_set(settings, "gtk-theme-name", fallback, nullptr);
    }

    g_autofree gchar* icon_theme_name = nullptr;
    g_object_get(settings, "gtk-icon-theme-name", &icon_theme_name, nullptr);
    const gchar* icon_fallback = available_icon_theme_fallback(prefer_dark);
    if (icon_fallback != nullptr && !icon_theme_exists(icon_theme_name)) {
      g_object_set(settings, "gtk-icon-theme-name", icon_fallback, nullptr);
    }
  }
}

static gboolean uses_legacy_yaru_window_shadow() {
  GtkSettings* settings = gtk_settings_get_default();
  if (settings == nullptr) {
    return FALSE;
  }

  g_autofree gchar* theme_name = nullptr;
  g_object_get(settings, "gtk-theme-name", &theme_name, nullptr);
  if (theme_name == nullptr) {
    return FALSE;
  }

  g_autofree gchar* normalized_theme = g_ascii_strdown(theme_name, -1);
  const gboolean is_yaru =
      g_strcmp0(normalized_theme, "yaru") == 0 ||
      g_str_has_prefix(normalized_theme, "yaru-");
  return is_yaru && strstr(normalized_theme, "highcontrast") == nullptr &&
         strstr(normalized_theme, "high-contrast") == nullptr;
}

static FlValue* local_paths_from_uris(gchar** uris) {
  FlValue* paths = fl_value_new_list();
  if (uris == nullptr) {
    return paths;
  }
  for (gchar** current = uris; *current != nullptr; current++) {
    g_autoptr(GError) error = nullptr;
    g_autofree gchar* path = g_filename_from_uri(*current, nullptr, &error);
    if (path != nullptr) {
      fl_value_append_take(paths, fl_value_new_string(path));
    }
  }
  return paths;
}

static void flush_open_paths(MyApplication* self) {
  if (!self->input_ready || !self->asset_input_channel || self->pending_paths->len == 0) return;
  g_autoptr(FlValue) paths = fl_value_new_list();
  for (guint index = 0; index < self->pending_paths->len; index++) {
    fl_value_append_take(paths, fl_value_new_string(static_cast<const char*>(g_ptr_array_index(self->pending_paths,index))));
  }
  g_ptr_array_set_size(self->pending_paths,0);
  fl_method_channel_invoke_method(self->asset_input_channel,"filesOpened",paths,nullptr,nullptr,nullptr);
}

static void asset_drag_data_received_cb(GtkWidget*,
                                        GdkDragContext* context,
                                        gint,
                                        gint,
                                        GtkSelectionData* selection,
                                        guint,
                                        guint time,
                                        gpointer user_data) {
  auto* self = MY_APPLICATION(user_data);
  g_auto(GStrv) uris = gtk_selection_data_get_uris(selection);
  g_autoptr(FlValue) paths = local_paths_from_uris(uris);
  const gboolean accepted = fl_value_get_length(paths) > 0;
  if (accepted) {
    for (size_t index = 0; index < fl_value_get_length(paths); index++) {
      g_ptr_array_add(self->pending_paths,g_strdup(fl_value_get_string(fl_value_get_list_value(paths,index))));
    }
    flush_open_paths(self);
  }
  gtk_drag_finish(context, accepted, FALSE, time);
}

static void register_asset_input_channel(MyApplication* self, FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->asset_input_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      kAssetInputChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->asset_input_channel,
    [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
      auto* owner=MY_APPLICATION(data);
      if (strcmp(fl_method_call_get_name(call),"ready")!=0) {
        fl_method_call_respond_not_implemented(call,nullptr);return;
      }
      owner->input_ready=TRUE;
      fl_method_call_respond_success(call,nullptr,nullptr);
      flush_open_paths(owner);
    },self,nullptr);

  GtkTargetEntry targets[] = {
      {const_cast<gchar*>("text/uri-list"), 0, 0},
  };
  gtk_drag_dest_set(GTK_WIDGET(view), GTK_DEST_DEFAULT_ALL, targets, 1,
                    GDK_ACTION_COPY);
  g_signal_connect(view, "drag-data-received",
                   G_CALLBACK(asset_drag_data_received_cb), self);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication*, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void release_window_resources(MyApplication* self) {
  // Release native children and their channels before GTK destroys the main
  // Flutter view/overlay. Application disposal happens after that destruction.
  busybooks_reader_host_free(self->reader_host);
  self->reader_host = nullptr;
  busybooks_linux_chrome_host_free(self->chrome_host);
  self->chrome_host = nullptr;
  busybooks_gtk_accent_host_free(self->gtk_accent_host);
  self->gtk_accent_host = nullptr;
  busybooks_native_menu_host_clear(&self->native_menu_channel);
  if (self->asset_input_channel) {
    fl_method_channel_set_method_call_handler(self->asset_input_channel, nullptr, nullptr, nullptr);
  }
  if (self->flutter_view) {
    g_signal_handlers_disconnect_by_func(self->flutter_view,
        reinterpret_cast<gpointer>(asset_drag_data_received_cb), self);
  }
  g_clear_object(&self->asset_input_channel);
  self->input_ready = FALSE;
  self->main_window = nullptr;
  self->flutter_view = nullptr;
  self->flutter_overlay = nullptr;
}

static void window_destroy_cb(GtkWidget*, gpointer data) {
  release_window_resources(MY_APPLICATION(data));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->main_window != nullptr) {gtk_window_present(self->main_window);return;}
  GtkWindow* window = GTK_WINDOW(hdy_application_window_new());
  gtk_application_add_window(GTK_APPLICATION(application), window);
  self->main_window = window;
  gtk_window_set_title(window, kApplicationDisplayName);
  gtk_widget_set_name(GTK_WIDGET(window), "busybooks-window");
  g_autoptr(GdkPixbuf) application_icon = load_application_icon();
  if (application_icon != nullptr) {
    gtk_window_set_default_icon(application_icon);
    gtk_window_set_icon(window, application_icon);
  }
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gtk_window_set_wmclass(window, APPLICATION_ID, APPLICATION_ID);
  G_GNUC_END_IGNORE_DEPRECATIONS
  if (application_icon == nullptr) {
    gtk_window_set_icon_name(window, APPLICATION_ID);
  }

  gtk_window_set_default_size(window, 1280, 720);
  if (uses_legacy_yaru_window_shadow()) {
    self->native_surface_css_provider = gtk_css_provider_new();
    gtk_css_provider_load_from_data(self->native_surface_css_provider,
        kLegacyYaruWindowShadowCompatibilityCss, -1, nullptr);
    gtk_style_context_add_provider_for_screen(gtk_widget_get_screen(GTK_WIDGET(window)),
        GTK_STYLE_PROVIDER(self->native_surface_css_provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  BusyBooksBindGtkViewRetirement(application, GTK_WIDGET(view));
  self->flutter_view = GTK_WIDGET(view);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));

  self->flutter_overlay = gtk_overlay_new();
  gtk_widget_set_hexpand(self->flutter_overlay, TRUE);
  gtk_widget_set_vexpand(self->flutter_overlay, TRUE);
  gtk_container_add(GTK_CONTAINER(self->flutter_overlay), GTK_WIDGET(view));
  gtk_widget_show(self->flutter_overlay);
  gtk_container_add(GTK_CONTAINER(window), self->flutter_overlay);

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  // Register before realizing the view starts Dart execution.
  self->gtk_accent_host = busybooks_gtk_accent_host_new(view, GTK_WIDGET(window));
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  self->chrome_host = busybooks_linux_chrome_host_new(view, window, set_gtk_theme_preference);
  self->native_menu_channel = busybooks_native_menu_host_new(view);
  register_asset_input_channel(self, view);
  self->reader_host = busybooks_reader_host_new(self->flutter_overlay, view);
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroy_cb), self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Remote file launches are delivered to the existing writer for this profile.
static int my_application_command_line(GApplication* application,
                                      GApplicationCommandLine* command_line) {
  auto* self=MY_APPLICATION(application);
  int count=0;
  g_auto(GStrv) arguments=g_application_command_line_get_arguments(command_line,&count);
  g_autoptr(GPtrArray) paths=g_ptr_array_new_with_free_func(g_free);
  for (int index=1;index<count;index++) {
    if (g_str_has_prefix(arguments[index],"--")) continue;
    g_autoptr(GFile) file=g_application_command_line_create_file_for_arg(command_line,arguments[index]);
    char* path=g_file_get_path(file);if(path)g_ptr_array_add(paths,path);
  }
  if (self->main_window == nullptr) {
    g_ptr_array_add(paths,nullptr);
    self->dart_entrypoint_arguments=g_strdupv(reinterpret_cast<gchar**>(paths->pdata));
    g_application_activate(application);
  } else {
    for(guint index=0;index<paths->len;index++)g_ptr_array_add(self->pending_paths,g_strdup(static_cast<const char*>(g_ptr_array_index(paths,index))));
    flush_open_paths(self);
    gtk_window_present(self->main_window);
  }
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  hdy_init();

}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  release_window_resources(self);
  if (self->native_surface_css_provider != nullptr) {
    GdkScreen* screen = gdk_screen_get_default();
    if (screen != nullptr) gtk_style_context_remove_provider_for_screen(screen, GTK_STYLE_PROVIDER(self->native_surface_css_provider));
  }
  g_clear_object(&self->native_surface_css_provider);
  g_clear_pointer(&self->pending_paths,g_ptr_array_unref);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}
static void my_application_init(MyApplication* self) {
  self->pending_paths=g_ptr_array_new_with_free_func(g_free);
  // The pinned gtk plugin registers a command-line signal handler when the
  // Flutter view starts. That runs before the class closure and otherwise
  // consumes remote launches without reaching BusyBooks' owned input queue.
  // Register first and stop further emission so each request has one owner.
  g_signal_connect(self,"command-line",G_CALLBACK(+[](GApplication* application,
      GApplicationCommandLine* command_line,gpointer)->gint {
    g_signal_stop_emission_by_name(application,"command-line");
    return my_application_command_line(application,command_line);
  }),nullptr);
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  g_set_application_name(kApplicationDisplayName);

  g_autofree char* identity=nullptr;
  const char* profile=g_getenv("BUSYBOOKS_PROFILE");
  if(profile&&*profile){g_autofree char* checksum=g_compute_checksum_for_string(G_CHECKSUM_SHA256,profile,-1);identity=g_strdup_printf("%s.p%.16s",APPLICATION_ID,checksum);}
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", identity?identity:APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE, nullptr));
}
