#include "reading_font_channel.h"
#include "../../native/reading_fonts.h"
#include <gio/gio.h>
#include <cstring>
#include <stdexcept>
#include <string>
#include <memory>
#include <mutex>
#include <condition_variable>

namespace {
struct ChannelState {
  std::mutex mutex;
  std::condition_variable finished;
  bool alive = true;
  int working = 0;
  bool Begin() { std::lock_guard<std::mutex> lock(mutex); if (!alive) return false; ++working; return true; }
  void End() { std::lock_guard<std::mutex> lock(mutex); --working; finished.notify_all(); }
  bool Alive() { std::lock_guard<std::mutex> lock(mutex); return alive; }
  void Close() { std::unique_lock<std::mutex> lock(mutex); alive = false; finished.wait(lock, [&] { return working == 0; }); }
};
using ChannelOwner = std::shared_ptr<ChannelState>;
struct Request {
  ChannelOwner owner;
  FlMethodCall* call;
  FlValue* result = nullptr;
  std::string error;
  Request(FlMethodCall* value, ChannelOwner state) : owner(std::move(state)), call(FL_METHOD_CALL(g_object_ref(value))) {}
  ~Request() { g_object_unref(call); if (result) fl_value_unref(result); }
};
FlValue* field(FlValue* args, const char* name) { return args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, name) : nullptr; }
std::string text(FlValue* args, const char* name) { auto* value = field(args, name); return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : ""; }
double number(FlValue* args, const char* name, double fallback) {
  auto* v = field(args, name); if (!v) return fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return fl_value_get_int(v);
  return fallback;
}
bool boolean(FlValue* args, const char* name) { auto* v = field(args, name); return v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(v); }
void worker(GTask* task, gpointer, gpointer data, GCancellable*) {
  auto* request = static_cast<Request*>(data);
  if (!request->owner->Begin()) { g_task_return_boolean(task, FALSE); return; }
  const std::string method = fl_method_call_get_name(request->call);
  auto* args = fl_method_call_get_args(request->call);
  try {
    if (method == "catalogue") {
      request->result = fl_value_new_list();
      for (const auto& family : reading_fonts::Discover(boolean(args, "refresh"))) {
        auto* item = fl_value_new_map();
        fl_value_set_string_take(item, "id", fl_value_new_string(family.id.c_str()));
        fl_value_set_string_take(item, "label", fl_value_new_string(family.label.c_str()));
        fl_value_append_take(request->result, item);
      }
    } else if (method == "resolve") {
      const auto result = reading_fonts::Resolve(text(args, "name"), boolean(args, "generic"));
      request->result = fl_value_new_map();
      fl_value_set_string_take(request->result, "family", fl_value_new_string(result.family.c_str()));
      auto* faces = fl_value_new_list();
      for (const auto& face : result.faces) {
        auto* item = fl_value_new_map(); auto* sources = fl_value_new_list();
        for (const auto& source : face.sources) fl_value_append_take(sources, fl_value_new_string(source.c_str()));
        fl_value_set_string_take(item, "sources", sources);
        fl_value_set_string_take(item, "weight", fl_value_new_int(face.weight));
        fl_value_set_string_take(item, "italic", fl_value_new_bool(face.italic));
        fl_value_append_take(faces, item);
      }
      fl_value_set_string_take(request->result, "faces", faces);
    } else if (method == "preview") {
      reading_fonts::Sample sample;
      sample.prose = text(args, "prose"); sample.bold = text(args, "bold"); sample.italic = text(args, "italic");
      if (sample.prose.size() + sample.bold.size() + sample.italic.size() > 4096) throw std::runtime_error("Font sample exceeds its limit");
      sample.width = number(args, "width", 360); sample.height = number(args, "height", 150);
      sample.scale = number(args, "scale", 1); sample.size = number(args, "size", 20); sample.line = number(args, "line", 1.5);
      sample.weight = number(args, "weight", 400);
      sample.foreground = number(args, "foreground", 0xff242424); sample.background = number(args, "background", 0xffffffff);
      auto bytes = reading_fonts::Preview(text(args, "name"), boolean(args, "generic"), sample);
      request->result = fl_value_new_uint8_list(bytes.data(), bytes.size());
    } else throw std::runtime_error("Unknown font request");
  } catch (const std::exception& error) { request->error = error.what(); }
  request->owner->End();
  g_task_return_boolean(task, TRUE);
}
void complete(GObject*, GAsyncResult* result, gpointer) {
  auto* request = static_cast<Request*>(g_task_get_task_data(G_TASK(result)));
  if (!request->owner->Alive()) return;
  if (request->error.empty()) fl_method_call_respond_success(request->call, request->result, nullptr);
  else fl_method_call_respond_error(request->call, "local-fonts", request->error.c_str(), nullptr, nullptr);
}
void call(FlMethodChannel*, FlMethodCall* method, gpointer data) {
  auto* request = new Request(method, *static_cast<ChannelOwner*>(data));
  g_autoptr(GTask) task = g_task_new(nullptr, nullptr, complete, nullptr);
  g_task_set_task_data(task, request, +[](gpointer value) { delete static_cast<Request*>(value); });
  // A private PangoCairo font map is created and destroyed on each worker. GTK's
  // default/main-thread map is never moved across threads.
  g_task_run_in_thread(task, worker);
}
}
FlMethodChannel* busybooks_reading_font_channel_new(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(messenger, "io.busystack.busybooks/reading_fonts", FL_METHOD_CODEC(codec));
  auto* owner = new ChannelOwner(std::make_shared<ChannelState>());
  fl_method_channel_set_method_call_handler(channel, call, owner, +[](gpointer data) {
    auto* owner = static_cast<ChannelOwner*>(data);
    // Native calls never wait on Flutter/main-thread work. Drain active Pango
    // work before the engine dies; queued requests see a closed owner and skip.
    (*owner)->Close(); delete owner;
  });
  return channel;
}
