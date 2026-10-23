#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <functional>
#include <string>

#include "flutter_window.h"
#include "utils.h"

static BOOL CALLBACK find_instance(HWND window,LPARAM value){auto* args=reinterpret_cast<std::pair<const wchar_t*,HWND>*>(value);if(GetPropW(window,args->first)){args->second=window;return FALSE;}return TRUE;}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  SetCurrentProcessExplicitAppUserModelID(L"io.busystack.busybooks");
  wchar_t profile[32768]{};GetEnvironmentVariableW(L"BUSYBOOKS_PROFILE",profile,32768);
  std::wstring instance=L"io.busystack.busybooks.instance."+std::to_wstring(std::hash<std::wstring>{}(profile));
  HANDLE mutex=CreateMutexW(nullptr,FALSE,instance.c_str());
  if(mutex&&GetLastError()==ERROR_ALREADY_EXISTS){
    std::pair<const wchar_t*,HWND> found{instance.c_str(),nullptr};
    for(int attempt=0;attempt<50&&!found.second;attempt++){EnumWindows(find_instance,reinterpret_cast<LPARAM>(&found));if(!found.second)Sleep(100);}
    if(!found.second){CloseHandle(mutex);return EXIT_FAILURE;}
    int count=0;auto** argv=CommandLineToArgvW(GetCommandLineW(),&count);
    std::wstring paths;for(int i=1;argv&&i<count;i++){if(wcsncmp(argv[i],L"--",2)==0)continue;if(!paths.empty())paths+=L'\n';paths+=argv[i];}
    if(!paths.empty()){COPYDATASTRUCT data{0x42424f4b,static_cast<DWORD>((paths.size()+1)*sizeof(wchar_t)),paths.data()};DWORD_PTR answer=0;SendMessageTimeoutW(found.second,WM_COPYDATA,0,reinterpret_cast<LPARAM>(&data),SMTO_ABORTIFHUNG,5000,&answer);}
    if(argv)LocalFree(argv);ShowWindow(found.second,SW_RESTORE);SetForegroundWindow(found.second);CloseHandle(mutex);return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"BusyBooks", origin, size)) {
    return EXIT_FAILURE;
  }
  SetPropW(window.GetHandle(),instance.c_str(),reinterpret_cast<HANDLE>(1));
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if(mutex)CloseHandle(mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
