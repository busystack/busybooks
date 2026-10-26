// Runs the production host and real TrackPopupMenuEx on an interactive desktop.
// Only the Flutter message transport is replaced; no Win32 menu API is mocked.
#include "../../windows/runner/native_menu_host.h"
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <cstdio>
#include <map>
#include <stdexcept>
#include <utility>
#include <vector>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {
void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
struct Reply {
  bool completed = false;
  EncodableValue value;
  std::string error;
};
class ProbeMessenger : public flutter::BinaryMessenger {
 public:
  void Send(const std::string&, const uint8_t*, size_t,
            flutter::BinaryReply reply) const override {
    if (reply) reply(nullptr, 0);
  }
  void SetMessageHandler(const std::string& channel,
                         flutter::BinaryMessageHandler handler) override {
    handlers_[channel] = std::move(handler);
  }
  void Call(const char* method, EncodableMap arguments, Reply& result) {
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    auto call = codec.EncodeMethodCall(flutter::MethodCall<EncodableValue>(
        method, std::make_unique<EncodableValue>(std::move(arguments))));
    handlers_.at("busybooks/native_menus")(
        call->data(), call->size(), [&result, &codec](const uint8_t* bytes, size_t size) {
          flutter::MethodResultFunctions<EncodableValue> receiver(
              [&result](const auto* value) {
                result.completed = true;
                if (value) result.value = *value;
              },
              [&result](const auto& code, const auto&, const auto*) {
                result.completed = true;
                result.error = code;
              },
              [&result] { result.completed = true; result.error = "not-implemented"; });
          if (!codec.DecodeAndProcessResponseEnvelope(bytes, size, &receiver)) {
            result.completed = true;
            result.error = "invalid-envelope";
          }
        });
  }
 private:
  std::map<std::string, flutter::BinaryMessageHandler> handlers_;
};

EncodableValue Entry(const char* label, bool enabled, bool selected) {
  return EncodableMap{{EncodableValue("label"), EncodableValue(label)},
                      {EncodableValue("enabled"), EncodableValue(enabled)},
                      {EncodableValue("checkable"), EncodableValue(true)},
                      {EncodableValue("mutuallyExclusive"), EncodableValue(true)},
                      {EncodableValue("selected"), EncodableValue(selected)}};
}
EncodableMap Arguments(int64_t session, bool disabled_selected = true) {
  return {{EncodableValue("sessionId"), EncodableValue(session)},
          {EncodableValue("entries"), EncodableList{
               Entry("Unavailable while loading", false, disabled_selected),
               Entry("Available command", true, !disabled_selected)}},
          {EncodableValue("anchor"), EncodableMap{
               {EncodableValue("x"), EncodableValue(40.0)},
               {EncodableValue("y"), EncodableValue(40.0)},
               {EncodableValue("width"), EncodableValue(40.0)},
               {EncodableValue("height"), EncodableValue(24.0)}}},
          {EncodableValue("preferredPosition"), EncodableValue("bottom")}};
}
void Key(WORD key) {
  INPUT inputs[2]{};
  inputs[0].type = inputs[1].type = INPUT_KEYBOARD;
  const UINT scan = MapVirtualKeyW(key, MAPVK_VK_TO_VSC_EX);
  inputs[0].ki.wScan = inputs[1].ki.wScan = static_cast<WORD>(scan & 0xff);
  inputs[0].ki.dwFlags = inputs[1].ki.dwFlags = KEYEVENTF_SCANCODE |
      ((scan & 0xff00) ? KEYEVENTF_EXTENDEDKEY : 0);
  inputs[1].ki.dwFlags |= KEYEVENTF_KEYUP;
  const UINT sent = SendInput(2, inputs, sizeof(INPUT));
  std::fprintf(stderr, "key=%u inserted=%u error=%lu\n", key, sent, GetLastError());
  if (sent != 2) EndMenu();
}
enum class Action { kKeyboard, kDisabledPointer, kDismiss };
struct Scenario {
  Action action = Action::kKeyboard;
  ProbeMessenger* messenger = nullptr;
  Reply* reply = nullptr;
  int64_t session = 0;
  HMENU menu = nullptr;
  bool disabled_selected = true;
  bool inspected = false;
  int stage = 0;
  ULONGLONG deadline = 0;
  std::string failure;
} scenario;

BOOL CALLBACK FindPopup(HWND window, LPARAM result) {
  wchar_t name[32]{};
  GetClassNameW(window, name, 32);
  if (!IsWindowVisible(window) || lstrcmpW(name, L"#32768") != 0) return TRUE;
  MENUBARINFO info{};
  info.cbSize = sizeof(MENUBARINFO);
  if (GetMenuBarInfo(window, OBJID_CLIENT, 0, &info) && info.hMenu) {
    *reinterpret_cast<HMENU*>(result) = info.hMenu;
    return FALSE;
  }
  return TRUE;
}

void CALLBACK Advance(HWND window, UINT, UINT_PTR, DWORD) {
  if (GetTickCount64() >= scenario.deadline) {
    scenario.failure = "Native popup interaction timed out";
    KillTimer(window, 1); EndMenu(); return;
  }
  // The production host uses TPM_NONOTIFY. Inspect the real popup through its
  // documented OBJID_CLIENT interface instead of waiting for notifications
  // that this presentation contract deliberately suppresses.
  if (!scenario.menu) {
    EnumThreadWindows(GetCurrentThreadId(), FindPopup,
                      reinterpret_cast<LPARAM>(&scenario.menu));
  }
  if (!scenario.menu) return;
  if (!scenario.inspected) {
    MENUITEMINFOW first{}, second{};
    first.cbSize = second.cbSize = sizeof(MENUITEMINFOW);
    first.fMask = second.fMask = MIIM_STATE | MIIM_FTYPE | MIIM_ID;
    const bool valid = GetMenuItemInfoW(scenario.menu, 0, TRUE, &first) &&
        GetMenuItemInfoW(scenario.menu, 1, TRUE, &second) &&
        (first.fState & MFS_DISABLED) && !(second.fState & MFS_DISABLED) &&
        (first.fType & MFT_RADIOCHECK) && (second.fType & MFT_RADIOCHECK) &&
        static_cast<bool>(first.fState & MFS_CHECKED) == scenario.disabled_selected &&
        static_cast<bool>(second.fState & MFS_CHECKED) != scenario.disabled_selected &&
        first.wID == 1 && second.wID == 2;
    scenario.inspected = true;
    if (!valid) scenario.failure = "Win32 enabled/radio/selection/index state mismatch";
  }
  if (!scenario.failure.empty()) { KillTimer(window, 1); EndMenu(); return; }
  if (scenario.action == Action::kDismiss) {
    KillTimer(window, 1);
    Reply dismissed;
    scenario.messenger->Call("dismiss", {{EncodableValue("sessionId"), EncodableValue(scenario.session)}}, dismissed);
    if (!dismissed.completed || dismissed.error.size() ||
        !std::get_if<bool>(&dismissed.value) || !std::get<bool>(dismissed.value)) {
      scenario.failure = "Active session did not dismiss";
    }
    return;
  }
  if (scenario.action == Action::kDisabledPointer && scenario.stage == 0) {
    RECT rect{};
    if (!GetMenuItemRect(window, scenario.menu, 0, &rect)) {
      scenario.failure = "Could not locate disabled native menu row";
      EndMenu(); return;
    }
    SetCursorPos((rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2);
    INPUT inputs[2]{};
    inputs[0].type = inputs[1].type = INPUT_MOUSE;
    inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(2, inputs, sizeof(INPUT));
    scenario.stage = 1;
    return;
  }
  if (scenario.reply->completed) scenario.failure = "Disabled row executed or dismissed the menu";
  if (scenario.stage < 2) {
    Key(VK_DOWN);
    scenario.stage = 2;
    return;
  }
  KillTimer(window, 1);
  Key(VK_RETURN);
}
void PumpUntil(Reply& reply) {
  const ULONGLONG deadline = GetTickCount64() + 10000;
  MSG message;
  while (!reply.completed && GetTickCount64() < deadline) {
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message); DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
  }
  Require(reply.completed, "Native menu request timed out");
}
void Exercise(HWND window, ProbeMessenger& messenger, int64_t session,
              Action action, bool disabled_selected) {
  scenario = Scenario{};
  scenario.action = action; scenario.session = session;
  scenario.messenger = &messenger; scenario.disabled_selected = disabled_selected;
  Reply reply;
  scenario.reply = &reply;
  scenario.deadline = GetTickCount64() + 8000;
  SetForegroundWindow(window);
  Require(SetTimer(window, 1, 250, Advance) != 0, "Could not start popup driver");
  messenger.Call("show", Arguments(session, disabled_selected), reply);
  PumpUntil(reply);
  KillTimer(window, 1);
  Require(reply.error.empty(), "Valid enabled/disabled radio group was rejected");
  Require(scenario.failure.empty(), scenario.failure.c_str());
  Require(scenario.inspected, "The actual Win32 popup was not presented");
  if (action == Action::kDismiss) {
    Require(std::holds_alternative<std::monostate>(reply.value), "Dismissal activated a command");
  } else {
    if (!std::get_if<int32_t>(&reply.value) || std::get<int32_t>(reply.value) != 1) {
      std::fprintf(stderr, "session=%lld result_type=%zu index=%d\n",
          static_cast<long long>(session), reply.value.index(),
          std::get_if<int32_t>(&reply.value) ? std::get<int32_t>(reply.value) : -1);
    }
    Require(std::get_if<int32_t>(&reply.value) && std::get<int32_t>(reply.value) == 1,
            "Wrong menu index or disabled command activation");
  }
  Require(GetForegroundWindow() == window, "Native menu lost owner focus");
}
}  // namespace

int main() {
  try {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    WNDCLASSW type{};
    type.hInstance = GetModuleHandleW(nullptr); type.lpfnWndProc = DefWindowProcW;
    type.lpszClassName = L"BusyBooksNativeMenuProbe";
    Require(RegisterClassW(&type) != 0, "Could not register probe window");
    HWND window = CreateWindowW(type.lpszClassName, L"BusyBooks native Win32 menu qualification",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE, 40, 40, 640, 400, nullptr, nullptr, type.hInstance, nullptr);
    Require(window != nullptr, "Could not create interactive probe window");
    ProbeMessenger messenger;
    int checks = 0;
    {
      NativeMenuHost host(window, &messenger);
      Reply invalid;
      auto arguments = Arguments(1);
      arguments[EncodableValue("entries")] = EncodableList{
          Entry("First", true, true), Entry("Second", false, true)};
      messenger.Call("show", std::move(arguments), invalid);
      Require(invalid.completed && invalid.error == "bad-arguments", "Multiple selected radio entries accepted");
      ++checks;
      Exercise(window, messenger, 2, Action::kKeyboard, true); ++checks;
      Exercise(window, messenger, 3, Action::kKeyboard, false); ++checks;
      Exercise(window, messenger, 4, Action::kDisabledPointer, true); ++checks;
      for (int64_t session = 5; session < 25; ++session) {
        Exercise(window, messenger, session, Action::kDismiss, true); ++checks;
      }
      Reply replaced, replacement;
      messenger.Call("show", Arguments(30), replaced);
      messenger.Call("show", Arguments(31), replacement);
      Require(replaced.completed && replaced.error.empty() &&
              std::holds_alternative<std::monostate>(replaced.value), "Superseded pending session retained");
      Reply dismiss;
      messenger.Call("dismiss", {{EncodableValue("sessionId"), EncodableValue(int64_t{31})}}, dismiss);
      Require(replacement.completed && replacement.error.empty(), "Pending replacement was not cancelled");
      ++checks;
    }
    {
      NativeMenuHost unavailable(nullptr, &messenger);
      Reply result;
      messenger.Call("show", Arguments(40), result);
      Require(result.completed && result.error == "unavailable", "Unavailable host did not report recoverable failure");
      ++checks;
    }
    DestroyWindow(window);
    std::printf("WINDOWS_MENU_PROBE passed checks=%d actual_win32_popups=23 disabled_activation=0 focus_restored=1\n", checks);
    return 0;
  } catch (const std::exception& error) {
    EndMenu(); std::fprintf(stderr, "WINDOWS_MENU_PROBE failed: %s\n", error.what()); return 1;
  }
}
