#ifndef BUSYBOOKS_WINDOWS_READER_HOST_H_
#define BUSYBOOKS_WINDOWS_READER_HOST_H_
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <WebView2.h>
#include <wrl.h>
#include <windows.h>
#include <cstddef>
#include <shellapi.h>
#include <sapi.h>
#include <memory>
#include <cstdint>
#include <string>
#include <vector>

class ReaderPopover;
class ReadingFontChannel;
class NativeMenuHost;
class ReaderHost {
 public:
  ReaderHost(HWND parent,flutter::BinaryMessenger* messenger);
  ~ReaderHost();
  void FilesDropped(HDROP drop);
  void FileOpened(const wchar_t* path);
  void AppearanceChanged();
  void WindowGeometryChanged();
  void SpeechEvents();
 private:
  void Initialize();
  void Event(const std::string& json, std::size_t limit = 1048576);
  std::shared_ptr<bool> alive_=std::make_shared<bool>(true);
  HWND parent_;
  std::unique_ptr<ReadingFontChannel> fonts_;
  std::unique_ptr<ReaderPopover> popover_;
  std::unique_ptr<NativeMenuHost> menus_;
  RECT bounds_{};
  uint32_t background_=0xfffafafa;
  bool visible_=false, input_ready_=false, speech_paused_=false, initializing_=false;
  ULONG speech_stream_=0;
  UINT64 navigation_id_=0;
  uint64_t initialization_generation_=0;
  std::string session_;
  std::vector<std::string> pending_files_;
  std::wstring publication_,cache_directory_,navigation_uri_,assets_,profile_;
  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> web_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_,input_,speech_,desktop_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
  Microsoft::WRL::ComPtr<ISpVoice> voice_;
};
#endif
