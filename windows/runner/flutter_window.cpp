#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  reader_host_=std::make_unique<ReaderHost>(flutter_controller_->view()->GetNativeWindow(),flutter_controller_->engine()->messenger());
  DragAcceptFiles(GetHandle(),TRUE);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  reader_host_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_COPYDATA: {
      auto* data=reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if(reader_host_&&data&&data->dwData==0x42424f4b&&data->cbData>=sizeof(wchar_t)&&data->cbData<=1048576&&data->cbData%sizeof(wchar_t)==0){
        auto* path=static_cast<const wchar_t*>(data->lpData);
        if(path&&path[data->cbData/sizeof(wchar_t)-1]==0){reader_host_->FileOpened(path);return TRUE;}
      }
      return FALSE;
    }
    case WM_APP+49:
      if(reader_host_)reader_host_->SpeechEvents();
      return 0;
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      if(reader_host_)reader_host_->AppearanceChanged();
      break;
    case WM_DROPFILES:
      if(reader_host_)reader_host_->FilesDropped(reinterpret_cast<HDROP>(wparam));
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
