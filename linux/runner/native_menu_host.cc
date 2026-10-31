// Adapted from BusyMark; shared by BusyBooks' primary and reader views.
#include "native_menu_host.h"
#include "native_shortcut_metadata.h"
#include "../../native/menu_selection.h"
#include <algorithm>
#include <cmath>
#include <cstring>
constexpr char kNativeMenuChannel[] = "busybooks/native_menus";
constexpr char kMenuAccelAttribute[] = "accel";
constexpr char kNativeMenuActionNamespace[] = "busybooks-native-menu";
constexpr char kNativeMenuActionIndexKey[] = "busybooks-native-menu-index";

static bool set_menu_item_accelerator(GMenuItem* item,
                                      const gchar* shortcut) {
  g_autofree gchar* accelerator =
      gtk_accelerator_from_shortcut_label(shortcut);
  if (accelerator != nullptr) {
    g_menu_item_set_attribute(item, kMenuAccelAttribute, "s", accelerator);
    return true;
  }
  return false;
}

static void respond_bool(FlMethodCall* method_call, gboolean value) {
  g_autoptr(FlValue) result = fl_value_new_bool(value);
  fl_method_call_respond_success(method_call, result, nullptr);
}

static const gchar* fl_lookup_string_arg(FlValue* args, const gchar* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

static gboolean fl_lookup_int64_arg(FlValue* args,
                                    const gchar* key,
                                    gint64* value_out) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FALSE;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return FALSE;
  }
  *value_out = fl_value_get_int(value);
  return TRUE;
}

static gboolean fl_lookup_double_arg(FlValue* args,
                                     const gchar* key,
                                     gdouble* value_out) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FALSE;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) {
    return FALSE;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    *value_out = fl_value_get_float(value);
    return TRUE;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    *value_out = static_cast<gdouble>(fl_value_get_int(value));
    return TRUE;
  }
  return FALSE;
}

static FlValue* fl_lookup_map_arg(FlValue* args, const gchar* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_MAP
             ? value
             : nullptr;
}
struct NativeMenuHandlerData;

struct NativeMenuSession {
  NativeMenuHandlerData* owner;
  gint64 id;
  GtkWidget* menu;
  GMenu* model;
  GSimpleActionGroup* action_group;
  FlMethodCall* method_call;
  gulong deactivate_signal_id;
  guint cleanup_source_id;
  gint pending_selected_index;
};

struct NativeMenuHandlerData {
  GtkWidget* view;
  NativeMenuSession* active;
  GdkEvent* trigger_event;
  gulong event_signal_id;
  gboolean enabled;
};

static gboolean native_menu_capture_trigger_event(GtkWidget*,
                                                  GdkEvent* event,
                                                  gpointer user_data) {
  auto* data = static_cast<NativeMenuHandlerData*>(user_data);
  if (event == nullptr ||
      (event->type != GDK_BUTTON_PRESS && event->type != GDK_KEY_PRESS &&
       event->type != GDK_TOUCH_BEGIN)) {
    return GDK_EVENT_PROPAGATE;
  }
  g_clear_pointer(&data->trigger_event, gdk_event_free);
  data->trigger_event = gdk_event_copy(event);
  return GDK_EVENT_PROPAGATE;
}

static void native_menu_session_respond(NativeMenuSession* session,
                                        gint selected_index) {
  if (session->method_call == nullptr) {
    return;
  }
  g_autoptr(FlValue) result = selected_index < 0
                                  ? fl_value_new_null()
                                  : fl_value_new_int(selected_index);
  fl_method_call_respond_success(session->method_call, result, nullptr);
  g_clear_object(&session->method_call);
}

static void native_menu_session_dispose(NativeMenuSession* session) {
  if (session == nullptr) {
    return;
  }
  NativeMenuHandlerData* owner = session->owner;
  if (owner != nullptr && owner->active == session) {
    owner->active = nullptr;
  }
  if (session->cleanup_source_id != 0) {
    g_source_remove(session->cleanup_source_id);
    session->cleanup_source_id = 0;
  }
  if (session->menu != nullptr) {
    if (session->deactivate_signal_id != 0) {
      g_signal_handler_disconnect(session->menu,
                                  session->deactivate_signal_id);
      session->deactivate_signal_id = 0;
    }
    if (gtk_widget_get_visible(session->menu)) {
      gtk_menu_shell_deactivate(GTK_MENU_SHELL(session->menu));
    }
  }
  if (owner != nullptr && owner->view != nullptr) {
    gtk_widget_insert_action_group(owner->view,
                                   kNativeMenuActionNamespace, nullptr);
  }
  if (session->menu != nullptr && GTK_IS_MENU(session->menu) &&
      gtk_menu_get_attach_widget(GTK_MENU(session->menu)) != nullptr) {
    gtk_menu_detach(GTK_MENU(session->menu));
  }
  g_clear_object(&session->menu);

  if (owner != nullptr && owner->view != nullptr) {
    if (owner->enabled && gtk_widget_get_mapped(owner->view) &&
        GTK_IS_WINDOW(gtk_widget_get_toplevel(owner->view)) &&
        gtk_window_is_active(GTK_WINDOW(gtk_widget_get_toplevel(owner->view)))) {
      gtk_widget_grab_focus(owner->view);
    }
  }
  g_clear_object(&session->model);
  g_clear_object(&session->action_group);
  native_menu_session_respond(session, session->pending_selected_index);
  g_free(session);
}

static gboolean native_menu_cleanup_idle_cb(gpointer user_data) {
  auto* session = static_cast<NativeMenuSession*>(user_data);
  session->cleanup_source_id = 0;
  native_menu_session_dispose(session);
  return G_SOURCE_REMOVE;
}

static void native_menu_deactivate_cb(GtkMenuShell*, gpointer user_data) {
  auto* session = static_cast<NativeMenuSession*>(user_data);
  if (session->cleanup_source_id == 0) {
    // GtkMenu deactivates before invoking the selected GAction. Let the
    // action run before resolving and freeing the native session.
    session->cleanup_source_id = g_idle_add_full(
        G_PRIORITY_DEFAULT_IDLE, native_menu_cleanup_idle_cb, session,
        nullptr);
  }
}

static void native_menu_action_activated_cb(GSimpleAction* action,
                                            GVariant*,
                                            gpointer user_data) {
  if (!g_action_get_enabled(G_ACTION(action))) return;
  auto* session = static_cast<NativeMenuSession*>(user_data);
  session->pending_selected_index =
      GPOINTER_TO_INT(
          g_object_get_data(G_OBJECT(action), kNativeMenuActionIndexKey)) -
      1;
}

static void native_menu_check_activated_cb(GSimpleAction* action,
                                           GVariant*,
                                           gpointer user_data) {
  g_autoptr(GVariant) state = g_action_get_state(G_ACTION(action));
  if (state == nullptr ||
      !g_variant_is_of_type(state, G_VARIANT_TYPE_BOOLEAN)) {
    return;
  }
  g_simple_action_set_state(
      action, g_variant_new_boolean(!g_variant_get_boolean(state)));
  native_menu_action_activated_cb(action, nullptr, user_data);
}

static gboolean native_menu_dismiss_active(NativeMenuHandlerData* data,
                                           gint64 session_id) {
  NativeMenuSession* session = data->active;
  if (session == nullptr || session->id != session_id) {
    return FALSE;
  }
  if (session->menu != nullptr && gtk_widget_get_visible(session->menu)) {
    gtk_menu_shell_deactivate(GTK_MENU_SHELL(session->menu));
  } else {
    native_menu_session_dispose(session);
  }
  return TRUE;
}

static gboolean fl_lookup_optional_bool_with_default(
    FlValue* args,
    const gchar* key,
    gboolean fallback,
    gboolean* value_out) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FALSE;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) {
    *value_out = fallback;
    return TRUE;
  }
  if (fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return FALSE;
  }
  *value_out = fl_value_get_bool(value);
  return TRUE;
}

static gboolean fl_lookup_positive_int64_arg(FlValue* args,
                                             const gchar* key,
                                             gint64* value_out) {
  if (!fl_lookup_int64_arg(args, key, value_out) || *value_out <= 0) {
    return FALSE;
  }
  return TRUE;
}

static void respond_native_menu_argument_error(FlMethodCall* method_call,
                                               const gchar* message) {
  fl_method_call_respond_error(method_call, "invalid-arguments", message,
                               nullptr, nullptr);
}

static gboolean parse_native_menu_anchor(FlValue* args,
                                         GdkRectangle* rectangle_out) {
  FlValue* anchor = fl_lookup_map_arg(args, "anchor");
  if (anchor == nullptr) {
    return FALSE;
  }
  gdouble x = 0;
  gdouble y = 0;
  gdouble width = 0;
  gdouble height = 0;
  if (!fl_lookup_double_arg(anchor, "x", &x) ||
      !fl_lookup_double_arg(anchor, "y", &y) ||
      !fl_lookup_double_arg(anchor, "width", &width) ||
      !fl_lookup_double_arg(anchor, "height", &height) ||
      !std::isfinite(x) || !std::isfinite(y) || !std::isfinite(width) ||
      !std::isfinite(height) || !std::isfinite(x + width) ||
      !std::isfinite(y + height) || width < 0 || height < 0) {
    return FALSE;
  }

  const gdouble left = std::floor(x);
  const gdouble top = std::floor(y);
  const gdouble right = std::ceil(x + width);
  const gdouble bottom = std::ceil(y + height);
  const gdouble pixel_width = std::max(1.0, right - left);
  const gdouble pixel_height = std::max(1.0, bottom - top);
  if (left < G_MININT || left > G_MAXINT || top < G_MININT ||
      top > G_MAXINT || right < G_MININT || right > G_MAXINT ||
      bottom < G_MININT || bottom > G_MAXINT || pixel_width > G_MAXINT ||
      pixel_height > G_MAXINT) {
    return FALSE;
  }

  rectangle_out->x = static_cast<gint>(left);
  rectangle_out->y = static_cast<gint>(top);
  rectangle_out->width = static_cast<gint>(pixel_width);
  rectangle_out->height = static_cast<gint>(pixel_height);
  return TRUE;
}

static GIcon* create_native_menu_icon(const gchar* icon_name, FlValue* entry) {
  if (icon_name == nullptr || icon_name[0] == '\0') {
    return nullptr;
  }

  FlValue* packed_color = fl_value_lookup_string(entry, "iconColor");
  GdkRGBA foreground = {0.5, 0.5, 0.5, 1.0};
  if (packed_color != nullptr &&
      fl_value_get_type(packed_color) == FL_VALUE_TYPE_INT) {
    const guint32 argb = static_cast<guint32>(fl_value_get_int(packed_color));
    foreground = {
        static_cast<gdouble>((argb >> 16) & 0xff) / 255.0,
        static_cast<gdouble>((argb >> 8) & 0xff) / 255.0,
        static_cast<gdouble>(argb & 0xff) / 255.0,
        static_cast<gdouble>((argb >> 24) & 0xff) / 255.0,
    };
  }



  if (packed_color != nullptr &&
      fl_value_get_type(packed_color) == FL_VALUE_TYPE_INT) {
    GtkIconInfo* icon_info = gtk_icon_theme_lookup_icon(
        gtk_icon_theme_get_default(), icon_name, 16,
        static_cast<GtkIconLookupFlags>(GTK_ICON_LOOKUP_FORCE_SIZE |
                                        GTK_ICON_LOOKUP_FORCE_SYMBOLIC));
    if (icon_info != nullptr) {
      gboolean was_symbolic = FALSE;
      g_autoptr(GError) error = nullptr;
      GdkPixbuf* pixbuf = gtk_icon_info_load_symbolic(
          icon_info, &foreground, nullptr, nullptr, nullptr, &was_symbolic,
          &error);
      g_object_unref(icon_info);
      if (pixbuf != nullptr) {
        return G_ICON(pixbuf);
      }
    }
  }

  return g_themed_icon_new(icon_name);
}

static gboolean validate_native_menu_entries(FlValue* entries,
                                              FlMethodCall* method_call,
                                              guint depth,
                                              size_t* entry_count) {
  if (depth > 8 || entries == nullptr ||
      fl_value_get_type(entries) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(entries) == 0 ||
      fl_value_get_length(entries) > 4096 - *entry_count) {
    respond_native_menu_argument_error(method_call, "Invalid or excessive submenu entries.");
    return FALSE;
  }
  *entry_count += fl_value_get_length(entries);
  size_t command_count = 0;
  MenuSelectionGroup selection_group;
  for (size_t index = 0; index < fl_value_get_length(entries); index++) {
    FlValue* entry = fl_value_get_list_value(entries, index);
    if (entry == nullptr || fl_value_get_type(entry) != FL_VALUE_TYPE_MAP) {
      respond_native_menu_argument_error(method_call, "Menu entries must be maps.");
      return FALSE;
    }
    FlValue* children = fl_value_lookup_string(entry, "children");
    FlValue* icon_color = entry == nullptr
                              ? nullptr
                              : fl_value_lookup_string(entry, "iconColor");
    gboolean separator = FALSE;
    gboolean enabled = TRUE;
    gboolean checkable = FALSE;
    gboolean selected = FALSE;
    gboolean mutually_exclusive = FALSE;
    if (entry == nullptr || fl_value_get_type(entry) != FL_VALUE_TYPE_MAP ||
        !fl_lookup_optional_bool_with_default(entry, "separator", FALSE,
                                              &separator) ||
        !fl_lookup_optional_bool_with_default(entry, "enabled", TRUE,
                                              &enabled) ||
        !fl_lookup_optional_bool_with_default(entry, "checkable", FALSE,
                                              &checkable) ||
        !fl_lookup_optional_bool_with_default(entry, "selected", FALSE,
                                              &selected) ||
        !fl_lookup_optional_bool_with_default(entry, "mutuallyExclusive",
                                              FALSE,
                                              &mutually_exclusive) ||
        (!separator && fl_lookup_string_arg(entry, "label") == nullptr) ||
        (fl_value_lookup_string(entry, "icon") != nullptr &&
         fl_value_get_type(fl_value_lookup_string(entry, "icon")) !=
             FL_VALUE_TYPE_STRING) ||
        (icon_color != nullptr &&
         (fl_value_get_type(icon_color) != FL_VALUE_TYPE_INT ||
          fl_value_get_int(icon_color) < 0 ||
          fl_value_get_int(icon_color) >
              static_cast<gint64>(G_MAXUINT32))) ||
        (selected && !checkable) ||
        (children != nullptr && (separator || checkable)) ||
        (fl_value_lookup_string(entry, "gtkAccelerator") != nullptr &&
         fl_lookup_string_arg(entry, "gtkAccelerator") == nullptr) ||
        (fl_value_lookup_string(entry, "shortcut") != nullptr &&
         fl_lookup_string_arg(entry, "shortcut") == nullptr)) {
      respond_native_menu_argument_error(
          method_call,
          "entries must contain valid command or separator presentation.");
      return FALSE;
    }
    if (children != nullptr &&
        !validate_native_menu_entries(children, method_call, depth + 1, entry_count)) {
      return FALSE;
    }
    if (!separator) {
      command_count++;
    }
    if (!selection_group.Add(separator, checkable, mutually_exclusive, selected)) {
      respond_native_menu_argument_error(
          method_call,
          "single-choice groups allow at most one selected entry.");
      return FALSE;
    }
  }
  if (command_count == 0) {
    respond_native_menu_argument_error(method_call,
                                       "entries must contain a command.");
    return FALSE;
  }

  return TRUE;
}

static gchar* escape_native_menu_label(const gchar* label) {
  GString* literal = g_string_new(nullptr);
  for (const gchar* cursor = label; *cursor != '\0'; cursor++) {
    if (*cursor == '_') {
      g_string_append_c(literal, '_');
    }
    g_string_append_c(literal, *cursor);
  }
  return g_string_free(literal, FALSE);
}

static void build_native_menu_model(FlValue* entries,
                                     NativeMenuSession* session,
                                     GMenu* model,
                                     size_t* next_index,
                                     gboolean ancestors_enabled) {
  GMenu* section = g_menu_new();
  guint section_length = 0;
  auto flush_section = [&]() {
    if (section_length > 0) {
      g_menu_append_section(model, nullptr, G_MENU_MODEL(section));
    }
    g_object_unref(section);
    section = g_menu_new();
    section_length = 0;
  };

  for (size_t index = 0; index < fl_value_get_length(entries); index++) {
    FlValue* entry = fl_value_get_list_value(entries, index);
    gboolean separator = FALSE;
    fl_lookup_optional_bool_with_default(entry, "separator", FALSE,
                                         &separator);
    if (separator) {
      flush_section();
      (*next_index)++;
      continue;
    }

    const size_t entry_index = (*next_index)++;
    const gchar* label = fl_lookup_string_arg(entry, "label");
    // GMenu's GtkMenu adapter treats underscores as mnemonic markers. Flutter
    // labels are literal presentation text, so double every underscore only at
    // this native boundary; action indexes and clipboard payloads stay intact.
    g_autofree gchar* literal_label = escape_native_menu_label(label);
    const gchar* icon_name = fl_lookup_string_arg(entry, "icon");
    // Accelerator metadata is generated from logical keys in Dart. GMenu uses
    // it for display; Flutter remains the single command dispatch mechanism.
    const gchar* shortcut = fl_lookup_string_arg(entry, "gtkAccelerator");
    if (shortcut == nullptr) shortcut = fl_lookup_string_arg(entry, "shortcut");
    gboolean enabled = TRUE;
    gboolean checkable = FALSE;
    gboolean selected = FALSE;
    gboolean exclusive = FALSE;
    fl_lookup_optional_bool_with_default(entry, "enabled", TRUE, &enabled);
    fl_lookup_optional_bool_with_default(entry, "checkable", FALSE,
                                         &checkable);
    fl_lookup_optional_bool_with_default(entry, "selected", FALSE,
                                         &selected);
    fl_lookup_optional_bool_with_default(entry, "mutuallyExclusive", FALSE,
                                         &exclusive);

    FlValue* children = fl_value_lookup_string(entry, "children");
    if (children != nullptr) {
      g_autoptr(GMenu) submenu = g_menu_new();
      build_native_menu_model(children, session, submenu, next_index,
                              ancestors_enabled && enabled);
      g_autoptr(GMenuItem) item =
          g_menu_item_new_submenu(literal_label, G_MENU_MODEL(submenu));
      g_menu_append_item(section, item);
      section_length++;
      continue;
    }
    g_autofree gchar* action_name = g_strdup_printf("select-%zu", entry_index);
    GSimpleAction* action = checkable && exclusive
                                ? g_simple_action_new_stateful(
                                      action_name, G_VARIANT_TYPE_STRING,
                                      g_variant_new_string(selected ? action_name : ""))
                                : checkable
                                ? g_simple_action_new_stateful(
                                      action_name, nullptr,
                                      g_variant_new_boolean(selected))
                                : g_simple_action_new(action_name, nullptr);
    g_simple_action_set_enabled(action, ancestors_enabled && enabled);
    g_object_set_data(G_OBJECT(action), kNativeMenuActionIndexKey,
                      GINT_TO_POINTER(static_cast<gint>(entry_index) + 1));
    g_signal_connect(
        action, "activate",
        G_CALLBACK(checkable && !exclusive ? native_menu_check_activated_cb
                             : native_menu_action_activated_cb),
        session);
    g_action_map_add_action(G_ACTION_MAP(session->action_group),
                            G_ACTION(action));

    g_autofree gchar* detailed_action =
        g_strdup_printf("%s.%s", kNativeMenuActionNamespace, action_name);
    g_autoptr(GMenuItem) item =
        g_menu_item_new(literal_label, detailed_action);
    if (checkable && exclusive) {
      g_menu_item_set_attribute(item, G_MENU_ATTRIBUTE_TARGET, "s", action_name);
    }
    if (icon_name != nullptr && icon_name[0] != '\0') {
      g_autoptr(GIcon) icon = create_native_menu_icon(icon_name, entry);
      g_menu_item_set_icon(item, icon);
    }
    if (shortcut != nullptr && shortcut[0] != '\0' &&
        !set_menu_item_accelerator(item, shortcut)) {
      const gchar* display = fl_lookup_string_arg(entry, "shortcut");
      if (display != nullptr && display[0] != '\0') {
        g_autofree gchar* fallback = g_strdup_printf("%s  (%s)", literal_label, display);
        g_menu_item_set_label(item, fallback);
      }
    }
    g_menu_append_item(section, item);
    g_object_unref(action);
    section_length++;
  }
  flush_section();
  g_object_unref(section);

}


// GtkMenu's model adapter does not bind submenu-heading sensitivity to an
// action. Apply availability to those actual GTK widgets, in model order.
// Sections can coalesce separators, so separators never consume a command row.
static gboolean set_native_submenu_availability(GtkWidget* menu,
                                                FlValue* entries,
                                                gboolean ancestors_enabled) {
  GList* rows = gtk_container_get_children(GTK_CONTAINER(menu));
  GList* row = rows;
  gboolean valid = TRUE;
  for (size_t index = 0; index < fl_value_get_length(entries); index++) {
    FlValue* entry = fl_value_get_list_value(entries, index);
    gboolean separator = FALSE;
    gboolean enabled = TRUE;
    fl_lookup_optional_bool_with_default(entry, "separator", FALSE, &separator);
    if (separator) continue;
    while (row != nullptr && GTK_IS_SEPARATOR_MENU_ITEM(row->data)) row = row->next;
    if (row == nullptr || !GTK_IS_MENU_ITEM(row->data)) {
      valid = FALSE;
      break;
    }
    fl_lookup_optional_bool_with_default(entry, "enabled", TRUE, &enabled);
    FlValue* children = fl_value_lookup_string(entry, "children");
    if (children != nullptr) {
      GtkWidget* submenu = gtk_menu_item_get_submenu(GTK_MENU_ITEM(row->data));
      gtk_widget_set_sensitive(GTK_WIDGET(row->data), ancestors_enabled && enabled);
      if (submenu == nullptr || !GTK_IS_MENU(submenu) ||
          !set_native_submenu_availability(submenu, children, ancestors_enabled && enabled)) {
        valid = FALSE;
        break;
      }
    }
    row = row->next;
  }
  g_list_free(rows);
  return valid;
}

static void set_native_menu_direction(GtkWidget* widget, gpointer data) {
  gtk_widget_set_direction(widget, static_cast<GtkTextDirection>(GPOINTER_TO_INT(data)));
  if (GTK_IS_MENU_ITEM(widget)) {
    GtkWidget* submenu = gtk_menu_item_get_submenu(GTK_MENU_ITEM(widget));
    if (submenu != nullptr) set_native_menu_direction(submenu, data);
  }
  if (GTK_IS_CONTAINER(widget)) {
    gtk_container_foreach(GTK_CONTAINER(widget), set_native_menu_direction, data);
  }
}

static void show_native_menu(NativeMenuHandlerData* data,
                             FlMethodCall* method_call,
                             FlValue* args) {
  if (data->view == nullptr || !gtk_widget_get_realized(data->view) ||
      gtk_widget_get_window(data->view) == nullptr) {
    fl_method_call_respond_error(method_call, "unavailable",
                                 "The native menu host is unavailable.",
                                 nullptr, nullptr);
    return;
  }
  if (!data->enabled || !gtk_widget_get_mapped(data->view)) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  GdkRectangle anchor = {};
  gint64 session_id = 0;
  if (!fl_lookup_positive_int64_arg(args, "sessionId", &session_id) ||
      !parse_native_menu_anchor(args, &anchor)) {
    respond_native_menu_argument_error(
        method_call,
        "sessionId must be positive and anchor must contain finite geometry.");
    return;
  }

  GtkWidget* toplevel = gtk_widget_get_toplevel(data->view);
  if (GTK_IS_WINDOW(toplevel) && !gtk_window_is_active(GTK_WINDOW(toplevel))) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  GdkWindow* rect_window =
      GTK_IS_WINDOW(toplevel) ? gtk_widget_get_window(toplevel) : nullptr;
  GdkRectangle window_anchor = anchor;
  if (rect_window == nullptr ||
      !gtk_widget_translate_coordinates(
          data->view, toplevel, anchor.x, anchor.y, &window_anchor.x,
          &window_anchor.y)) {
    fl_method_call_respond_error(
        method_call, "unavailable",
        "GTK could not translate the menu anchor into window coordinates.",
        nullptr, nullptr);
    return;
  }

  FlValue* entries = fl_value_lookup_string(args, "entries");
  const gchar* direction_arg = fl_lookup_string_arg(args, "textDirection");
  if (fl_value_lookup_string(args, "textDirection") != nullptr &&
      g_strcmp0(direction_arg, "ltr") != 0 &&
      g_strcmp0(direction_arg, "rtl") != 0) {
    respond_native_menu_argument_error(method_call, "textDirection must be ltr or rtl.");
    return;
  }
  const GtkTextDirection direction = direction_arg == nullptr
      ? gtk_widget_get_direction(data->view)
      : (g_strcmp0(direction_arg, "rtl") == 0 ? GTK_TEXT_DIR_RTL : GTK_TEXT_DIR_LTR);
  gboolean focus_first = FALSE;
  const gchar* preferred_position_arg =
      fl_lookup_string_arg(args, "preferredPosition");
  GtkPositionType preferred_position = GTK_POS_BOTTOM;
  if (g_strcmp0(preferred_position_arg, "top") == 0) {
    preferred_position = GTK_POS_TOP;
  } else if (preferred_position_arg != nullptr &&
             g_strcmp0(preferred_position_arg, "bottom") != 0) {
    respond_native_menu_argument_error(
        method_call, "preferredPosition must be top or bottom.");
    return;
  }
  if (entries == nullptr ||
      fl_value_get_type(entries) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(entries) == 0 ||
      fl_value_get_length(entries) > static_cast<size_t>(G_MAXINT) ||
      !fl_lookup_optional_bool_with_default(args, "focusFirst", FALSE,
                                            &focus_first)) {
    respond_native_menu_argument_error(
        method_call,
        "entries must be non-empty and focusFirst must be boolean.");
    return;
  }

  size_t entry_count = 0;
  if (!validate_native_menu_entries(entries, method_call, 0, &entry_count)) return;
  if (data->active != nullptr) {
    native_menu_session_dispose(data->active);
  }

  auto* session = g_new0(NativeMenuSession, 1);
  session->owner = data;
  session->id = session_id;
  session->pending_selected_index = -1;
  session->method_call =
      FL_METHOD_CALL(g_object_ref(G_OBJECT(method_call)));
  session->action_group = g_simple_action_group_new();
  session->model = g_menu_new();
  data->active = session;

  size_t next_index = 0;
  build_native_menu_model(entries, session, session->model, &next_index, TRUE);
  // GtkPopover maps as a Wayland subsurface whose frame callback can stall
  // while Flutter's parent surface is idle. GtkMenu maps as an independent
  // native xdg_popup instead.
  gtk_widget_insert_action_group(
      data->view, kNativeMenuActionNamespace,
      G_ACTION_GROUP(session->action_group));
  session->menu = gtk_menu_new_from_model(G_MENU_MODEL(session->model));
  if (session->menu == nullptr || !GTK_IS_MENU(session->menu)) {
    fl_method_call_respond_error(method_call, "unavailable",
                                 "GTK could not create the native menu.",
                                 nullptr, nullptr);
    g_clear_object(&session->method_call);
    native_menu_session_dispose(session);
    return;
  }
  g_object_ref_sink(session->menu);
  gtk_menu_attach_to_widget(GTK_MENU(session->menu), data->view, nullptr);
  set_native_menu_direction(session->menu, GINT_TO_POINTER(direction));
  gtk_widget_show_all(session->menu);
  if (!set_native_submenu_availability(session->menu, entries, TRUE)) {
    fl_method_call_respond_error(method_call, "invalid-menu",
                                 "GTK menu rows do not match the menu model.",
                                 nullptr, nullptr);
    g_clear_object(&session->method_call);
    native_menu_session_dispose(session);
    return;
  }
  session->deactivate_signal_id = g_signal_connect(
      session->menu, "deactivate", G_CALLBACK(native_menu_deactivate_cb),
      session);

  const gboolean open_above = preferred_position == GTK_POS_TOP;
  const gboolean rtl = direction == GTK_TEXT_DIR_RTL;
  g_object_set(session->menu, "anchor-hints",
               GDK_ANCHOR_FLIP_Y | GDK_ANCHOR_SLIDE | GDK_ANCHOR_RESIZE,
               nullptr);
  if (!open_above) {
    g_object_set(session->menu, "menu-type-hint",
                 GDK_WINDOW_TYPE_HINT_DROPDOWN_MENU, nullptr);
  }
  // Flutter reports view-local coordinates, while FlView is a no-window
  // widget below the native titlebar. Use the translated toplevel rectangle
  // directly instead of a hidden proxy whose GTK allocation is deferred.
  gtk_menu_popup_at_rect(
      GTK_MENU(session->menu), rect_window, &window_anchor,
      open_above ? (rtl ? GDK_GRAVITY_NORTH_EAST : GDK_GRAVITY_NORTH_WEST)
                 : (rtl ? GDK_GRAVITY_SOUTH_EAST : GDK_GRAVITY_SOUTH_WEST),
      open_above ? (rtl ? GDK_GRAVITY_SOUTH_EAST : GDK_GRAVITY_SOUTH_WEST)
                 : (rtl ? GDK_GRAVITY_NORTH_EAST : GDK_GRAVITY_NORTH_WEST),
      data->trigger_event);
  if (focus_first) {
    gtk_menu_shell_select_first(GTK_MENU_SHELL(session->menu), TRUE);
  } else {
    gtk_menu_shell_deselect(GTK_MENU_SHELL(session->menu));
  }
}

static void native_menu_handler_data_free(gpointer user_data) {
  auto* data = static_cast<NativeMenuHandlerData*>(user_data);
  if (data->active != nullptr) {
    native_menu_session_dispose(data->active);
  }
  if (data->view != nullptr) {
    if (data->event_signal_id != 0) {
      g_signal_handler_disconnect(data->view, data->event_signal_id);
    }
    g_object_remove_weak_pointer(
        G_OBJECT(data->view),
        reinterpret_cast<gpointer*>(&data->view));
  }
  g_clear_pointer(&data->trigger_event, gdk_event_free);
  g_free(data);
}

static void native_menu_method_call_cb(FlMethodChannel*,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  auto* data = static_cast<NativeMenuHandlerData*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, "show") == 0) {
    show_native_menu(data, method_call, fl_method_call_get_args(method_call));
  } else if (strcmp(method, "dismiss") == 0) {
    gint64 session_id = 0;
    if (!fl_lookup_positive_int64_arg(fl_method_call_get_args(method_call),
                                      "sessionId", &session_id)) {
      respond_native_menu_argument_error(
          method_call, "sessionId must be a positive integer.");
      return;
    }
    respond_bool(method_call,
                 native_menu_dismiss_active(data, session_id));
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

FlMethodChannel* busybooks_native_menu_host_new(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      kNativeMenuChannel, FL_METHOD_CODEC(codec));
  auto* data = g_new0(NativeMenuHandlerData, 1);
  data->view = GTK_WIDGET(view);
  data->enabled = TRUE;
  g_object_add_weak_pointer(G_OBJECT(data->view),
                            reinterpret_cast<gpointer*>(&data->view));
  data->event_signal_id =
      g_signal_connect(data->view, "event",
                       G_CALLBACK(native_menu_capture_trigger_event), data);
  fl_method_channel_set_method_call_handler(
      channel, native_menu_method_call_cb, data,
      native_menu_handler_data_free);
  g_object_set_data(G_OBJECT(channel), "busybooks-native-menu-host", data);
  return channel;
}

void busybooks_native_menu_host_set_enabled(FlMethodChannel* channel, gboolean enabled) {
  if (!channel) return;
  auto* data = static_cast<NativeMenuHandlerData*>(
      g_object_get_data(G_OBJECT(channel), "busybooks-native-menu-host"));
  if (!data) return;
  data->enabled = enabled;
  if (!enabled && data->active) native_menu_session_dispose(data->active);
}

void busybooks_native_menu_host_clear(FlMethodChannel** channel) {
  if (!channel || !*channel) return;
  busybooks_native_menu_host_set_enabled(*channel, FALSE);
  g_object_set_data(G_OBJECT(*channel), "busybooks-native-menu-host", nullptr);
  // The messenger retains this channel until engine shutdown. Dropping only
  // our reference would retain callbacks and GTK trigger events past the view.
  fl_method_channel_set_method_call_handler(*channel, nullptr, nullptr, nullptr);
  g_clear_object(channel);
}
