#include "reading_font_channel.h"
#include "../../native/reading_fonts.h"
#include <flutter/standard_method_codec.h>
#include <stdexcept>
using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
namespace {
constexpr UINT completed = WM_APP + 71;
const EncodableValue* field(const EncodableMap& args, const char* name) { auto i = args.find(EncodableValue(name)); return i == args.end() ? nullptr : &i->second; }
std::string text(const EncodableMap& args, const char* name) { auto* v = field(args, name); auto* s = v ? std::get_if<std::string>(v) : nullptr; return s ? *s : ""; }
bool boolean(const EncodableMap& args, const char* name) { auto* v = field(args, name); auto* b = v ? std::get_if<bool>(v) : nullptr; return b && *b; }
double number(const EncodableMap& args, const char* name, double fallback) {
  auto* v = field(args, name); if (!v) return fallback;
  if (auto* n = std::get_if<double>(v)) return *n;
  if (auto* n = std::get_if<int32_t>(v)) return *n;
  if (auto* n = std::get_if<int64_t>(v)) return static_cast<double>(*n);
  return fallback;
}
EncodableValue execute(const std::string& method, const EncodableMap& args) {
  if (method == "catalogue") {
    EncodableList list;
    for (const auto& f : reading_fonts::Discover(boolean(args, "refresh"))) list.emplace_back(EncodableMap{{EncodableValue("id"), EncodableValue(f.id)}, {EncodableValue("label"), EncodableValue(f.label)}});
    return EncodableValue(list);
  }
  if (method == "resolve") {
    auto result = reading_fonts::Resolve(text(args, "name"), boolean(args, "generic")); EncodableList faces;
    for (const auto& f : result.faces) {
      EncodableList sources; for (const auto& s : f.sources) sources.emplace_back(s);
      faces.emplace_back(EncodableMap{{EncodableValue("sources"), EncodableValue(sources)}, {EncodableValue("weight"), EncodableValue(f.weight)}, {EncodableValue("italic"), EncodableValue(f.italic)}});
    }
    return EncodableValue(EncodableMap{{EncodableValue("family"), EncodableValue(result.family)}, {EncodableValue("faces"), EncodableValue(faces)}});
  }
  if (method == "preview") {
    reading_fonts::Sample sample;
    sample.prose = text(args, "prose"); sample.bold = text(args, "bold"); sample.italic = text(args, "italic");
    if (sample.prose.size() + sample.bold.size() + sample.italic.size() > 4096) throw std::runtime_error("Font sample exceeds its limit");
    sample.width = static_cast<int>(number(args, "width", 360)); sample.height = static_cast<int>(number(args, "height", 150));
    sample.scale = number(args, "scale", 1); sample.size = number(args, "size", 20); sample.line = number(args, "line", 1.5);
    sample.weight = static_cast<int>(number(args, "weight", 400));
    sample.foreground = static_cast<uint32_t>(number(args, "foreground", 0xff242424)); sample.background = static_cast<uint32_t>(number(args, "background", 0xffffffff));
    return EncodableValue(reading_fonts::Preview(text(args, "name"), boolean(args, "generic"), sample));
  }
  throw std::runtime_error("Unknown font request");
}
}
struct ReadingFontChannel::Job {
  std::string method, error;
  EncodableMap args;
  EncodableValue value;
  std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
};
ReadingFontChannel::ReadingFontChannel(flutter::BinaryMessenger* messenger) {
  WNDCLASSW wc{}; wc.lpfnWndProc = Procedure; wc.hInstance = GetModuleHandleW(nullptr); wc.lpszClassName = L"BusyBooksReadingFonts"; RegisterClassW(&wc);
  window_ = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "io.busystack.busybooks/reading_fonts", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (!window_) { result->Error("local-fonts", "Font worker is unavailable"); return; }
    auto job = std::make_unique<Job>(); job->method = call.method_name(); job->result = std::move(result);
    if (call.arguments()) { if (auto* args = std::get_if<EncodableMap>(call.arguments())) job->args = *args; }
    { std::lock_guard<std::mutex> lock(mutex_); jobs_.push_back(std::move(job)); }
    changed_.notify_one();
  });
  worker_ = std::thread([this] { Work(); });
}
ReadingFontChannel::~ReadingFontChannel() {
  channel_->SetMethodCallHandler(nullptr);
  { std::lock_guard<std::mutex> lock(mutex_); stopping_ = true; jobs_.clear(); }
  changed_.notify_one(); if (worker_.joinable()) worker_.join();
  if (window_) {
    MSG msg{}; while (PeekMessageW(&msg, window_, completed, completed, PM_REMOVE)) delete reinterpret_cast<Job*>(msg.lParam);
    DestroyWindow(window_);
  }
}
void ReadingFontChannel::Work() {
  for (;;) {
    std::unique_ptr<Job> job;
    { std::unique_lock<std::mutex> lock(mutex_); changed_.wait(lock, [&] { return stopping_ || !jobs_.empty(); }); if (stopping_) return; job = std::move(jobs_.front()); jobs_.pop_front(); }
    try { job->value = execute(job->method, job->args); } catch (const std::exception& error) { job->error = error.what(); }
    if (PostMessageW(window_, completed, 0, reinterpret_cast<LPARAM>(job.get()))) job.release();
  }
}
LRESULT CALLBACK ReadingFontChannel::Procedure(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == completed) {
    std::unique_ptr<Job> job(reinterpret_cast<Job*>(lparam));
    // Flutter replies stay on the engine's platform thread.
    if (job->error.empty()) job->result->Success(job->value); else job->result->Error("local-fonts", job->error);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
