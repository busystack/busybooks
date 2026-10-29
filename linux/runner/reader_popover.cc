#include "reader_popover.h"
#include "native_menu_host.h"
#include "../../native/reader_action_limits.h"
#include "../../native/reader_popover_events.h"
#include "../../native/reader_popover_geometry.h"
#include <gdk/gdkkeysyms.h>
#include <cstring>
#include <algorithm>
#include <cmath>
// Opt-in, bounded stage diagnostics. Never serialize publication/draft payloads.
void ReaderPopover::Trace(const char* stage) const {
  if (g_strcmp0(g_getenv("BUSYBOOKS_READER_DIAGNOSTICS"), "1") != 0) return;
  auto* kind = data_ ? fl_value_lookup_string(data_, "kind") : nullptr;
  auto* session = data_ ? fl_value_lookup_string(data_, "session") : nullptr;
  auto* owner = data_ ? fl_value_lookup_string(data_, "presentation") : nullptr;
  g_message("reader-popup stage=%s kind=%s session=%s presentation=%" G_GINT64_FORMAT
      " backend=%s build=%s ready=%d frame=%d painted=%d requested=%d mapped=%d",
      stage, kind && fl_value_get_type(kind) == FL_VALUE_TYPE_STRING ? fl_value_get_string(kind) : "none",
      session && fl_value_get_type(session) == FL_VALUE_TYPE_STRING ? fl_value_get_string(session) : "none",
      owner && fl_value_get_type(owner) == FL_VALUE_TYPE_INT ? fl_value_get_int(owner) : 0,
      G_OBJECT_TYPE_NAME(gtk_widget_get_display(anchor_)),
#ifdef NDEBUG
      "release",
#else
      "debug",
#endif
      ready_, frame_, painted_, requested_, popover_ && gtk_widget_get_mapped(popover_));
}
ReaderPopover::ReaderPopover(GtkWidget* anchor, std::function<void(const char*)> event)
    : anchor_(GTK_WIDGET(g_object_ref(anchor))), event_(std::move(event)) {}
ReaderPopover::~ReaderPopover() {
  Trace("destroy");
  *alive_ = false;
  busybooks_native_menu_host_clear(&menu_channel_);
  Complete("popover-cancelled");
  if (channel_) fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  if (view_) g_signal_handlers_disconnect_by_data(view_, this);
  if (popover_) { gtk_widget_destroy(popover_); g_object_unref(popover_); }
  g_clear_object(&channel_);
  g_clear_object(&view_);
  g_clear_object(&anchor_);
  if (data_) fl_value_unref(data_);
}
void ReaderPopover::EnsureView() {
  if (restart_) {
    Trace("restart");
    busybooks_native_menu_host_clear(&menu_channel_);
    if (channel_) fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
    if (view_) g_signal_handlers_disconnect_by_data(view_, this);
    if (popover_) { gtk_widget_destroy(popover_); g_object_unref(popover_); popover_ = nullptr; }
    g_clear_object(&channel_); g_clear_object(&view_);
    ready_ = false; frame_ = false; restart_ = false;
  }
  if (popover_) return;
  Trace("create");
  popover_ = gtk_popover_new(anchor_);
  g_object_ref_sink(popover_);
  gtk_popover_set_position(GTK_POPOVER(popover_), GTK_POS_BOTTOM);
  gtk_popover_set_modal(GTK_POPOVER(popover_), TRUE);
  g_signal_connect(popover_, "key-press-event", G_CALLBACK(+[](GtkWidget*, GdkEventKey* key, gpointer data) -> gboolean {
    auto* self = static_cast<ReaderPopover*>(data);
    if (key->keyval == GDK_KEY_Escape) self->keyboard_dismissal_ = true;
    return FALSE;
  }), this);
  g_signal_connect(popover_, "closed", G_CALLBACK(+[](GtkPopover* popover, gpointer data) {
    auto* self = static_cast<ReaderPopover*>(data);
    // GTK emits closed synchronously, before its hide animation clears widget
    // visibility. Invalidate the owning presentation at that signal, not later.
    if (GTK_WIDGET(popover) != self->popover_) return;
    self->Hide();
  }), this);
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  char argument[] = "--busybooks-reader-popover";
  char* arguments[] = {argument, nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(project, arguments);
  // The pinned engine creates an EGL manager during fl_view_new. A GDK/GLX
  // context from the owning view must not remain current on this GTK thread.
  gdk_gl_context_clear_current();
  view_ = fl_view_new(project);
  g_object_ref_sink(view_);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view_)),
      "io.busystack.busybooks/reader_popover", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, Call, this, nullptr);
  menu_channel_ = busybooks_native_menu_host_new(view_);
  busybooks_native_menu_host_set_enabled(menu_channel_, FALSE);
  g_signal_connect(view_, "first-frame", G_CALLBACK(Frame), this);
  gtk_container_add(GTK_CONTAINER(popover_), GTK_WIDGET(view_));
  gtk_widget_show(GTK_WIDGET(view_));
  // Realize starts the engine; a transparent, nonmodal allocation below lets
  // Flutter produce frames without presenting an empty interactive popup.
  // Widget setup can realize children; also release the context before any
  // remaining compositor initialization on explicit realization.
  gdk_gl_context_clear_current();
  gtk_widget_realize(popover_);
  Trace("realized");
}
void ReaderPopover::Show(FlMethodCall* call) {
  auto* data = fl_method_call_get_args(call);
  if (!data || fl_value_get_type(data) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_error(call, "popover-payload", "Invalid reader controls", nullptr, nullptr);
    return;
  }
  auto* parent = gtk_widget_get_toplevel(anchor_);
  if (!GTK_IS_WINDOW(parent) || !gtk_widget_get_mapped(parent) || !gtk_window_is_active(GTK_WINDOW(parent))) {
    fl_method_call_respond_error(call, "popover-cancelled", "Reader window is inactive", nullptr, nullptr);
    return;
  }
  auto number = [data](const char* key, double fallback) {
    auto* v = fl_value_lookup_string(data, key);
    double n = v && fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT ? fl_value_get_float(v) : fallback;
    return std::isfinite(n) ? n : fallback;
  };
  const ReaderPopoverRect pane{number("viewportX", 0), number("viewportY", 0),
      number("viewportWidth", 0), number("viewportHeight", 0)};
  if (!ValidReaderPopoverRect(pane)) {
    fl_method_call_respond_error(call, "popover-payload", "Invalid reader pane", nullptr, nullptr);
    return;
  }
  Hide();
  EnsureView();
  if (data_) fl_value_unref(data_);
  data_ = fl_value_ref(data);
  pending_ = FL_METHOD_CALL(g_object_ref(call));
  requested_ = true;
  Trace("show-valid-viewport");
  painted_ = false;
  GdkRectangle work{};
  auto* monitor = gdk_display_get_monitor_at_window(gtk_widget_get_display(anchor_), gtk_widget_get_window(parent));
  if (!monitor) { Complete("popover-unavailable"); requested_ = false; return; }
  gdk_monitor_get_workarea(monitor, &work);
  const auto placement = PlaceReaderPopover(pane,
      {number("x", 0), number("y", 0), std::max(1.0, number("anchorWidth", 1)),
       std::max(1.0, number("anchorHeight", 1))},
      std::min(number("width", 460), static_cast<double>(work.width)),
      std::min(number("height", 360), static_cast<double>(work.height)), 12, true);
  const GdkRectangle rect{static_cast<int>(std::round(placement.pointing_x)),
      static_cast<int>(std::round(placement.pointing_y)), 1, 1};
  gtk_popover_set_position(GTK_POPOVER(popover_), placement.above ? GTK_POS_TOP : GTK_POS_BOTTOM);
  gtk_popover_set_pointing_to(GTK_POPOVER(popover_), &rect);
  maximum_height_ = static_cast<int>(std::ceil(placement.body.height));
  gtk_widget_set_size_request(GTK_WIDGET(view_), static_cast<int>(std::ceil(placement.body.width)), maximum_height_);
  // Mapping is necessary for a GL surface/frame clock. Keep it transparent and
  // nonmodal until the current payload has actually painted, never on ready alone.
  gtk_widget_set_opacity(popover_, 0);
  gtk_popover_set_modal(GTK_POPOVER(popover_), FALSE);
  gtk_popover_popup(GTK_POPOVER(popover_));
  timeout_ = g_timeout_add_seconds(15, Timeout, this);
  Update();
}
void ReaderPopover::Complete(const char* code) {
  if (timeout_) { g_source_remove(timeout_); timeout_ = 0; }
  if (!pending_) return;
  Trace(code ? code : "presented");
  if (code) {
    g_autoptr(FlValue) details = fl_value_new_map();
    fl_value_set_string_take(details, "ready", fl_value_new_bool(ready_));
    fl_value_set_string_take(details, "firstFrame", fl_value_new_bool(frame_));
    fl_value_set_string_take(details, "painted", fl_value_new_bool(painted_));
    fl_method_call_respond_error(pending_, code, "Reader controls could not be presented. Try again.", details, nullptr);
  }
  else fl_method_call_respond_success(pending_, nullptr, nullptr);
  g_clear_object(&pending_);
}
bool ReaderPopover::Matches(FlValue* value) const {
  if (!data_ || !value || fl_value_get_type(value) != FL_VALUE_TYPE_MAP) return false;
  for (const char* key : {"session", "presentation"}) {
    auto* a = fl_value_lookup_string(data_, key);
    auto* b = fl_value_lookup_string(value, key);
    if (!a || !b || !fl_value_equal(a, b)) return false;
  }
  return true;
}
gboolean ReaderPopover::Timeout(gpointer data) {
  auto* self = static_cast<ReaderPopover*>(data);
  self->timeout_ = 0;
  self->Trace("timeout");
  self->restart_ = !self->ready_;
  self->Complete("popover-timeout");
  self->Hide();
  return G_SOURCE_REMOVE;
}
void ReaderPopover::Present() {
  if (!requested_ || !painted_ || !frame_ || !gtk_widget_get_mapped(anchor_) || !gtk_widget_get_mapped(popover_)) return;
  auto* parent = gtk_widget_get_toplevel(anchor_);
  if (!GTK_IS_WINDOW(parent) || !gtk_window_is_active(GTK_WINDOW(parent))) { Hide(); return; }
  if (pending_) Trace("reveal");
  busybooks_native_menu_host_set_enabled(menu_channel_, TRUE);
  gtk_popover_set_modal(GTK_POPOVER(popover_), TRUE);
  gtk_widget_set_opacity(popover_, 1);
  if (pending_) gtk_widget_grab_focus(GTK_WIDGET(view_));
  Complete();
}
void ReaderPopover::Result(FlValue* data) {
  if(channel_) fl_method_channel_invoke_method(channel_, "result", data, nullptr, nullptr, nullptr);
}
void ReaderPopover::Capture(FlMethodCall* call) {
  if (!channel_ || !ready_) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  fl_method_channel_invoke_method(channel_, "capture", fl_method_call_get_args(call), nullptr,
      [](GObject* object, GAsyncResult* result, gpointer data) {
        auto* pending = FL_METHOD_CALL(data);
        g_autoptr(GError) error = nullptr;
        g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
            FL_METHOD_CHANNEL(object), result, &error);
        if (response) fl_method_call_respond(pending, response, nullptr);
        else fl_method_call_respond_error(pending, "reader-draft-unavailable",
            error ? error->message : "Note delivery could not be confirmed", nullptr, nullptr);
        g_object_unref(pending);
      }, g_object_ref(call));
}
void ReaderPopover::Hide() {
  if (requested_) Trace("hide");
  busybooks_native_menu_host_set_enabled(menu_channel_, FALSE);
  const bool notify = requested_;
  const bool keyboard = keyboard_dismissal_;
  keyboard_dismissal_ = false;
  requested_ = false;
  painted_ = false;
  Complete("popover-cancelled");
  if (popover_) gtk_popover_popdown(GTK_POPOVER(popover_));
  if (notify && data_) {
    if (channel_) fl_method_channel_invoke_method(channel_, "hidden", data_, nullptr, nullptr, nullptr);
    auto* session = fl_value_lookup_string(data_, "session");
    auto* presentation = fl_value_lookup_string(data_, "presentation");
    if (session && presentation && fl_value_get_type(session) == FL_VALUE_TYPE_STRING &&
        fl_value_get_type(presentation) == FL_VALUE_TYPE_INT) {
      const auto event = ReaderPopoverHiddenEvent(fl_value_get_string(session), fl_value_get_int(presentation), keyboard);
      event_(event.c_str());
    }
  }
}
void ReaderPopover::Update() {
  if (!ready_ || !requested_ || !data_) return;
  Trace("payload-send");
  struct Reply { ReaderPopover* self; std::shared_ptr<bool> alive; FlValue* owner; };
  auto* reply = new Reply{this, alive_, fl_value_ref(data_)};
  fl_method_channel_invoke_method(channel_, "update", data_, nullptr,
      [](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<Reply> reply(static_cast<Reply*>(data));
        g_autoptr(GError) error = nullptr;
        g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(object), result, &error);
        auto* self = reply->self;
        if (*reply->alive && self->requested_ && self->Matches(reply->owner)) self->Trace(response && !FL_IS_METHOD_ERROR_RESPONSE(response) ? "payload-ack" : "payload-failed");
        if (*reply->alive && self->requested_ && self->Matches(reply->owner) &&
            (!response || FL_IS_METHOD_ERROR_RESPONSE(response))) {
          self->Complete("popover-payload"); self->Hide();
        }
        fl_value_unref(reply->owner);
      }, reply);
}
void ReaderPopover::Frame(FlView*, gpointer data) {
  auto* self = static_cast<ReaderPopover*>(data);
  self->frame_ = true;
  self->Trace("native-first-frame");
  self->Present();
}
void ReaderPopover::Call(FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
  auto* self = static_cast<ReaderPopover*>(data);
  if (channel != self->channel_) { fl_method_call_respond_error(call, "popover-cancelled", "Reader controls were replaced", nullptr, nullptr); return; }
  const char* name = fl_method_call_get_name(call);
  if (strcmp(name, "ready") == 0) {
    self->ready_ = true;
    self->Trace("ready");
    fl_method_call_respond_success(call, nullptr, nullptr);
    self->Update();
    return;
  }
  auto* value = fl_method_call_get_args(call);
  if ((strcmp(name, "presented") == 0 || strcmp(name, "failed") == 0)) {
    if (self->requested_ && self->Matches(value)) {
      self->Trace(strcmp(name, "failed") == 0 ? "dart-content-failed" : "dart-painted");
      if (strcmp(name, "failed") == 0) { self->Complete("popover-content"); self->Hide(); }
      else {
        auto* height = fl_value_lookup_string(value, "height");
        auto* kind = fl_value_lookup_string(self->data_, "kind");
        if (height && fl_value_get_type(height) == FL_VALUE_TYPE_FLOAT && kind &&
            (strcmp(fl_value_get_string(kind), "goto") == 0 || strcmp(fl_value_get_string(kind), "lookup") == 0)) {
          const double n = fl_value_get_float(height);
          if (std::isfinite(n) && n > 0) {
            int width = 0, maximum = 0; gtk_widget_get_size_request(GTK_WIDGET(self->view_), &width, &maximum);
            gtk_widget_set_size_request(GTK_WIDGET(self->view_), width, static_cast<int>(std::ceil(std::clamp(n, 1.0, static_cast<double>(self->maximum_height_)))));
          }
        }
        self->painted_ = true; self->Present();
      }
    }
    fl_method_call_respond_success(call, nullptr, nullptr); return;
  }

  if (strcmp(name, "action") == 0 && value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
    const char* json = fl_value_get_string(value);
    if(strlen(json)>kMaxReaderPopoverActionBytes){fl_method_call_respond_error(call,"reader-action-size","Reader action exceeds its UTF-8 byte limit",nullptr,nullptr);return;}
    self->event_(json);
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}
