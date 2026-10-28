#include "reader_popover.h"
#include "../../native/reader_action_limits.h"
#include "../../native/reader_popover_events.h"
#include "../../native/reader_popover_geometry.h"
#include <flutter/dart_project.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <cmath>
#include <flutter/method_result_functions.h>
#include <filesystem>
using flutter::EncodableValue;
using flutter::EncodableMap;
ReaderPopover::ReaderPopover(HWND anchor, std::function<void(const std::string&)> event)
    : anchor_(anchor), event_(std::move(event)) {}
ReaderPopover::~ReaderPopover() {
  *alive_ = false;
  Complete("popover-cancelled");
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  channel_.reset(); controller_.reset();
  if (window_) DestroyWindow(window_);
}
bool ReaderPopover::EnsureView() {
  if (controller_) return true;
  if(window_){DestroyWindow(window_);window_=nullptr;}
  WNDCLASSW wc{};
  wc.lpfnWndProc = Procedure;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"BusyBooksReaderPopover";
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&wc);
  window_ = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"BusyBooks",
      WS_POPUP | WS_BORDER | WS_CLIPCHILDREN, 0, 0, 460, 360,
      GetAncestor(anchor_, GA_ROOT), nullptr, wc.hInstance, this);
  if (!window_) return false;
  wchar_t executable[32768];
  if (!GetModuleFileNameW(nullptr, executable, 32768)) return false;
  flutter::DartProject project((std::filesystem::path(executable).parent_path() / L"data").wstring());
  project.set_dart_entrypoint_arguments({"--busybooks-reader-popover"});
  controller_ = std::make_unique<flutter::FlutterViewController>(460, 360, project);
  if (!controller_->engine() || !controller_->view()) { controller_.reset(); return false; }
  HWND child = controller_->view()->GetNativeWindow();
  SetParent(child, window_);
  SetWindowLongPtrW(child, GWL_STYLE, WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS);
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      controller_->engine()->messenger(), "io.busystack.busybooks/reader_popover",
      &flutter::StandardMethodCodec::GetInstance());
  const auto engine_generation = ++engine_generation_;
  channel_->SetMethodCallHandler([this, engine_generation](const auto& call, auto result) {
    if (engine_generation != engine_generation_) { result->Error("popover-cancelled", "Reader controls were replaced"); return; }
    if (call.method_name() == "ready") {
      ready_ = true; result->Success(); Update(); return;
    }
    if (call.method_name() == "presented" || call.method_name() == "failed") {
      if (call.arguments() && requested_ && Matches(*call.arguments())) {
        if (call.method_name() == "failed") { Complete("popover-content"); Hide(); }
        else Present(*call.arguments());
      }
      result->Success(); return;
    }
    const auto* json = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (call.method_name() == "action" && json) {
      if(json->size()>kMaxReaderPopoverActionBytes){result->Error("reader-action-size","Reader action exceeds its UTF-8 byte limit");return;}
      event_(*json); result->Success(); return;
    }
    result->NotImplemented();
  });
  return true;
}
void ReaderPopover::Show(const EncodableValue& data, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* map = std::get_if<EncodableMap>(&data);
  if (!map) { result->Error("popover-payload", "Invalid reader controls"); return; }
  HWND owner=GetAncestor(anchor_,GA_ROOT),foreground=GetForegroundWindow();
  if(IsIconic(owner)||(foreground!=owner&&foreground!=window_)){result->Error("popover-cancelled", "Reader window is inactive");return;}
  auto number = [map](const char* name, double fallback) {
    auto it = map->find(EncodableValue(name));
    if (it == map->end()) return fallback;
    double n = fallback;
    if (auto v = std::get_if<double>(&it->second)) n = *v;
    if (auto v = std::get_if<int32_t>(&it->second)) n = static_cast<double>(*v);
    return std::isfinite(n) ? n : fallback;
  };
  const ReaderPopoverRect pane{number("viewportX", 0), number("viewportY", 0),
      number("viewportWidth", 0), number("viewportHeight", 0)};
  if (!ValidReaderPopoverRect(pane)) { result->Error("popover-payload", "Invalid reader pane"); return; }
  Hide();
  if (restart_) {
    if (channel_) channel_->SetMethodCallHandler(nullptr);
    channel_.reset(); controller_.reset();
    if (window_) { DestroyWindow(window_); window_ = nullptr; }
    ready_ = false; restart_ = false;
  }
  data_ = data;
  pending_ = std::move(result); requested_ = true;
  if (!EnsureView()) { Complete("popover-unavailable"); requested_ = false; return; }
  const double scale = GetDpiForWindow(anchor_) / 96.0;
  POINT point{static_cast<LONG>(number("x", 0) * scale), static_cast<LONG>(number("y", 0) * scale)};
  ClientToScreen(anchor_, &point);
  MONITORINFO monitor{sizeof(MONITORINFO)};
  GetMonitorInfoW(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST), &monitor);
  POINT pane_top{static_cast<LONG>(pane.x * scale), static_cast<LONG>(pane.y * scale)};
  POINT pane_bottom{static_cast<LONG>((pane.x + pane.width) * scale), static_cast<LONG>((pane.y + pane.height) * scale)};
  ClientToScreen(anchor_, &pane_top); ClientToScreen(anchor_, &pane_bottom);
  const RECT pane_screen{pane_top.x, pane_top.y, pane_bottom.x, pane_bottom.y};
  if (!IntersectRect(&placement_bounds_, &pane_screen, &monitor.rcWork)) {
    Complete("popover-unavailable"); Hide(); return;
  }
  const auto placement = PlaceReaderPopover(
      {static_cast<double>(placement_bounds_.left), static_cast<double>(placement_bounds_.top),
       static_cast<double>(placement_bounds_.right - placement_bounds_.left),
       static_cast<double>(placement_bounds_.bottom - placement_bounds_.top)},
      {static_cast<double>(point.x), static_cast<double>(point.y),
       std::max(1.0, number("anchorWidth", 1) * scale), std::max(1.0, number("anchorHeight", 1) * scale)},
      number("width", 460) * scale, number("height", 360) * scale, 12 * scale);
  const int width = static_cast<int>(placement.body.width);
  const int height = static_cast<int>(placement.body.height);
  maximum_height_ = height;
  SetWindowPos(window_, HWND_TOP, static_cast<int>(placement.body.x), static_cast<int>(placement.body.y), width, height, SWP_NOACTIVATE);
  RECT client{}; GetClientRect(window_, &client);
  MoveWindow(controller_->view()->GetNativeWindow(), 0, 0, client.right, client.bottom, TRUE);
  SetTimer(window_, 1, 15000, nullptr);
  Update(); controller_->ForceRedraw();
}
void ReaderPopover::Result(const EncodableValue& data) { if(channel_) channel_->InvokeMethod("result", std::make_unique<EncodableValue>(data)); }
void ReaderPopover::Capture(const EncodableValue* args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (!channel_ || !ready_) { result->Success(); return; }
  channel_->InvokeMethod("capture", args ? std::make_unique<EncodableValue>(*args) : nullptr,
      std::move(result));
}
void ReaderPopover::Complete(const char* code) {
  if (window_) KillTimer(window_, 1);
  if (!pending_) return;
  if (code) pending_->Error(code, "Reader controls could not be presented. Try again.");
  else pending_->Success();
  pending_.reset();
}
bool ReaderPopover::Matches(const EncodableValue& value) const {
  const auto* current = std::get_if<EncodableMap>(&data_);
  const auto* incoming = std::get_if<EncodableMap>(&value);
  if (!current || !incoming) return false;
  for (const char* key : {"session", "presentation"}) {
    auto a = current->find(EncodableValue(key)), b = incoming->find(EncodableValue(key));
    if (a == current->end() || b == incoming->end() || !(a->second == b->second)) return false;
  }
  return true;
}
void ReaderPopover::Present(const EncodableValue& value) {
  const auto* map = std::get_if<EncodableMap>(&value);
  const auto* current = std::get_if<EncodableMap>(&data_);
  const auto kind = current->find(EncodableValue("kind"));
  if (kind != current->end() && (kind->second == EncodableValue("goto") || kind->second == EncodableValue("lookup") || kind->second == EncodableValue("appearance"))) {
    auto it = map->find(EncodableValue("height"));
    const auto* n = it == map->end() ? nullptr : std::get_if<double>(&it->second);
    if (n && std::isfinite(*n) && *n > 0) {
      RECT rect{}, client{}; GetWindowRect(window_, &rect); GetClientRect(window_, &client);
      int height = static_cast<int>(std::ceil(std::clamp(*n * GetDpiForWindow(anchor_) / 96.0, 1.0, static_cast<double>(maximum_height_))));
      auto number = [current](const char* key, double fallback) {
        auto it = current->find(EncodableValue(key));
        if (it != current->end()) { if (auto value = std::get_if<double>(&it->second)) return *value; }
        return fallback;
      };
      const double scale = GetDpiForWindow(anchor_) / 96.0;
      POINT point{static_cast<LONG>(number("x", 0) * scale), static_cast<LONG>(number("y", 0) * scale)};
      ClientToScreen(anchor_, &point);
      int width = rect.right - rect.left;
      const auto placement = PlaceReaderPopover(
          {static_cast<double>(placement_bounds_.left), static_cast<double>(placement_bounds_.top),
           static_cast<double>(placement_bounds_.right - placement_bounds_.left),
           static_cast<double>(placement_bounds_.bottom - placement_bounds_.top)},
          {static_cast<double>(point.x), static_cast<double>(point.y),
           std::max(1.0, number("anchorWidth", 1) * scale), std::max(1.0, number("anchorHeight", 1) * scale)},
          width, height, 12 * scale);
      SetWindowPos(window_, nullptr, static_cast<int>(placement.body.x), static_cast<int>(placement.body.y),
          static_cast<int>(placement.body.width), static_cast<int>(placement.body.height), SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }
  auto owner = data_; auto alive = alive_;
  controller_->engine()->SetNextFrameCallback([this, alive, owner]() {
    if (!*alive || !requested_ || !Matches(owner)) return;
    HWND parent = GetAncestor(anchor_, GA_ROOT), foreground = GetForegroundWindow();
    if (IsIconic(parent) || (foreground != parent && foreground != window_)) { Hide(); return; }
    ShowWindow(window_, SW_SHOWNOACTIVATE);
    if (pending_) SetFocus(controller_->view()->GetNativeWindow());
    Complete();
  });
  controller_->ForceRedraw();
}
void ReaderPopover::Hide() {
  const bool notify = requested_;
  requested_ = false; Complete("popover-cancelled");
  if (window_) ShowWindow(window_, SW_HIDE);
  const auto* map = std::get_if<EncodableMap>(&data_);
  if (notify && map) {
    if (channel_) channel_->InvokeMethod("hidden", std::make_unique<EncodableValue>(data_));
    auto session = map->find(EncodableValue("session"));
    auto presentation = map->find(EncodableValue("presentation"));
    if (session != map->end() && presentation != map->end()) {
      const auto* text = std::get_if<std::string>(&session->second);
      const auto* presentation32 = std::get_if<int32_t>(&presentation->second);
      const auto* presentation64 = std::get_if<int64_t>(&presentation->second);
      if (text && (presentation32 || presentation64)) event_(ReaderPopoverHiddenEvent(*text, presentation32 ? *presentation32 : *presentation64));
    }
  }
}
void ReaderPopover::Update() {
  if (!ready_ || !requested_) return;
  auto owner = data_; auto alive = alive_;
  auto fail = [this, alive, owner]() { if (*alive && requested_ && Matches(owner)) { Complete("popover-payload"); Hide(); } };
  channel_->InvokeMethod("update", std::make_unique<EncodableValue>(data_),
    std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
      [](const EncodableValue*) {}, [fail](const std::string&, const std::string&, const EncodableValue*) { fail(); }, fail));
}
LRESULT CALLBACK ReaderPopover::Procedure(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<ReaderPopover*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<ReaderPopover*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self && message == WM_TIMER && wparam == 1) { self->restart_ = !self->ready_; self->Complete("popover-timeout"); self->Hide(); return 0; }
  if (self && self->controller_) {
    auto result = self->controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }
  if (self && (message == WM_CLOSE || (message == WM_ACTIVATE && LOWORD(wparam) == WA_INACTIVE))) {
    self->Hide(); return 0;
  }
  if (self && message == WM_SIZE && self->controller_) {
    RECT rect{}; GetClientRect(hwnd, &rect);
    MoveWindow(self->controller_->view()->GetNativeWindow(), 0, 0, rect.right, rect.bottom, TRUE);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
