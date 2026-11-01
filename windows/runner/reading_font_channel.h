#ifndef BUSYBOOKS_READING_FONT_CHANNEL_H_
#define BUSYBOOKS_READING_FONT_CHANNEL_H_
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <thread>
class ReadingFontChannel {
 public:
  explicit ReadingFontChannel(flutter::BinaryMessenger* messenger);
  ~ReadingFontChannel();
 private:
  struct Job;
  static LRESULT CALLBACK Procedure(HWND, UINT, WPARAM, LPARAM);
  void Work();
  HWND window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::thread worker_;
  std::mutex mutex_;
  std::condition_variable changed_;
  std::deque<std::unique_ptr<Job>> jobs_;
  bool stopping_ = false;
};
#endif
