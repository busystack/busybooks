#ifndef BUSYBOOKS_WINDOWS_READER_POPOVER_H_
#define BUSYBOOKS_WINDOWS_READER_POPOVER_H_
#include <windows.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <functional>
#include <cstdint>
#include <memory>
#include <string>
class ReadingFontChannel;
class ReaderPopover {
 public:
  ReaderPopover(HWND anchor, std::function<void(const std::string&)> event);
  ~ReaderPopover();
  void Show(const flutter::EncodableValue& data, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Hide();
  void Result(const flutter::EncodableValue& data);
  void Capture(const flutter::EncodableValue* args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
 private:
  bool EnsureView();
  void Update();
  bool Matches(const flutter::EncodableValue& data) const;
  void Complete(const char* code = nullptr);
  void Present(const flutter::EncodableValue& data);
  static LRESULT CALLBACK Procedure(HWND, UINT, WPARAM, LPARAM);
  HWND anchor_, window_ = nullptr;
  std::unique_ptr<ReadingFontChannel> fonts_;
  std::function<void(const std::string&)> event_;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  flutter::EncodableValue data_;
  bool ready_ = false, requested_ = false, restart_ = false, font_chooser_ = false;
  int maximum_height_ = 480;
  uint64_t engine_generation_ = 0;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
};
#endif
