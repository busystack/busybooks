#ifndef BUSYBOOKS_WINDOWS_NATIVE_MENU_HOST_H_
#define BUSYBOOKS_WINDOWS_NATIVE_MENU_HOST_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
class NativeMenuHost {
 public:
  NativeMenuHost(HWND anchor, flutter::BinaryMessenger* messenger,
                 HWND active_owner = nullptr);
  ~NativeMenuHost();
  void SetEnabled(bool enabled);
 private:
  struct Request;
  static LRESULT CALLBACK Procedure(HWND, UINT, WPARAM, LPARAM);
  void Present();
  HWND anchor_, active_owner_, messages_ = nullptr;
  bool enabled_ = true;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
  std::shared_ptr<Request> pending_, active_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
