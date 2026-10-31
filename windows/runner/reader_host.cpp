#include "reader_host.h"
#include "reading_font_channel.h"
#include "native_menu_host.h"
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shellapi.h>
#include <commctrl.h>
#include <sapi.h>
#include <dwmapi.h>
// The SDK's SAPI helper definitions still call GetVersionExW internally.
// Isolate that external-header deprecation; application warnings stay fatal.
#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4996)
#endif
#include <sphelper.h>
#ifdef _MSC_VER
#pragma warning(pop)
#endif
#include <filesystem>
#include <vector>
#include <algorithm>
using Microsoft::WRL::Callback;
using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
static std::wstring wide(const std::string& value){if(value.empty())return {};int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);std::wstring out(n,0);MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),out.data(),n);return out;}
static std::string utf8(const wchar_t* value){if(!value)return {};int n=WideCharToMultiByte(CP_UTF8,0,value,-1,nullptr,0,nullptr,nullptr);std::string out(n,0);WideCharToMultiByte(CP_UTF8,0,value,-1,out.data(),n,nullptr,nullptr);if(!out.empty())out.pop_back();return out;}
static const EncodableValue* field(const EncodableMap& map,const char* key){auto it=map.find(EncodableValue(key));return it==map.end()?nullptr:&it->second;}
static std::string stringField(const EncodableMap& map,const char* key){auto v=field(map,key);auto text=v?std::get_if<std::string>(v):nullptr;return text?*text:"";}
static double number(const EncodableMap& map,const char* key){auto v=field(map,key);if(!v)return 0;if(auto d=std::get_if<double>(v))return *d;if(auto i=std::get_if<int32_t>(v))return *i;return 0;}
ReaderHost::ReaderHost(HWND parent,flutter::BinaryMessenger* messenger):parent_(parent){
  wchar_t executable[MAX_PATH];GetModuleFileNameW(nullptr,executable,MAX_PATH);assets_=(std::filesystem::path(executable).parent_path()/L"data/flutter_assets/assets/reader").wstring();
  wchar_t temp[MAX_PATH];GetTempPathW(MAX_PATH,temp);GUID id;CoCreateGuid(&id);wchar_t guid[40];StringFromGUID2(id,guid,40);profile_=(std::filesystem::path(temp)/(std::wstring(L"busybooks-webview-")+guid)).wstring();
  channel_=std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger,"io.busystack.busybooks/reader",&flutter::StandardMethodCodec::GetInstance());
  input_=std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger,"com.busybooks.app/asset_input",&flutter::StandardMethodCodec::GetInstance());
  input_->SetMethodCallHandler([this](const auto& call,auto result){
    if(call.method_name()!="ready"){result->NotImplemented();return;}
    input_ready_=true;EncodableList paths;for(const auto& path:pending_files_)paths.emplace_back(path);pending_files_.clear();
    result->Success();if(!paths.empty())input_->InvokeMethod("filesOpened",std::make_unique<EncodableValue>(paths));
  });
  fonts_=std::make_unique<ReadingFontChannel>(messenger);
  menus_=std::make_unique<NativeMenuHost>(parent_,messenger);
  channel_->SetMethodCallHandler([this](const auto& call,auto result){
    const auto& name=call.method_name();
    if(name=="capture"){
      DismissHeaderHint();
      if(!web_||capture_){result->Error("reader-capture","Reader is unavailable or capture is pending");return;}
      Microsoft::WRL::ComPtr<IStream> stream; stream.Attach(SHCreateMemStream(nullptr,0));
      if(!stream){result->Error("reader-capture","Could not create frame stream");return;}
      capture_=std::shared_ptr<flutter::MethodResult<EncodableValue>>(std::move(result));
      std::weak_ptr<flutter::MethodResult<EncodableValue>> reply=capture_;
      auto session=session_;auto alive=alive_;
      HRESULT started=web_->CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG,stream.Get(),
        Callback<ICoreWebView2CapturePreviewCompletedHandler>([this,alive,reply,session,stream](HRESULT status)->HRESULT {
          if(!*alive)return S_OK;
          auto pending=reply.lock();if(!pending)return S_OK;
          if(capture_==pending)capture_.reset();
          if(FAILED(status)||session!=session_){pending->Error("reader-capture","Reader frame is obsolete or unavailable");return S_OK;}
          STATSTG stat{};LARGE_INTEGER start{};ULONG read=0;
          if(FAILED(stream->Stat(&stat,STATFLAG_NONAME))||stat.cbSize.QuadPart>64*1024*1024||FAILED(stream->Seek(start,STREAM_SEEK_SET,nullptr))){pending->Error("reader-capture","Invalid reader frame");return S_OK;}
          std::vector<uint8_t> bytes(static_cast<size_t>(stat.cbSize.QuadPart));
          if(FAILED(stream->Read(bytes.data(),static_cast<ULONG>(bytes.size()),&read))||read!=bytes.size()){pending->Error("reader-capture","Incomplete reader frame");return S_OK;}
          pending->Success(EncodableValue(bytes));return S_OK;
        }).Get());
      if(FAILED(started)){capture_->Error("reader-capture","Reader capture failed");capture_.reset();}
      return;
    }else if(name=="headerHint"){
      const auto* map=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;
      const auto* rect=map&&field(*map,"anchor")?std::get_if<EncodableMap>(field(*map,"anchor")):nullptr;
      if(!map||!rect){result->Error("header-hint","Missing hint anchor");return;}
      auto* id=field(*map,"id");const auto* identity=id?std::get_if<int32_t>(id):nullptr;
      const auto* identity64=id?std::get_if<int64_t>(id):nullptr;
      hint_id_=identity?*identity:identity64?*identity64:0;
      hint_text_=wide(stringField(*map,"message"));
      HWND owner=GetAncestor(parent_,GA_ROOT);
      if(GetForegroundWindow()!=owner){result->Success();return;}
      if(!hint_){
        // Use the operating system tooltip control without adding a package or
        // another Flutter view. Common controls are an existing Windows component.
        static HMODULE module=LoadLibraryW(L"comctl32.dll");
        using Init=BOOL(WINAPI*)(const INITCOMMONCONTROLSEX*);
        auto initialize=module?reinterpret_cast<Init>(GetProcAddress(module,"InitCommonControlsEx")):nullptr;
        INITCOMMONCONTROLSEX controls{sizeof(controls),ICC_WIN95_CLASSES};if(initialize)initialize(&controls);
        hint_=CreateWindowExW(WS_EX_TOPMOST|WS_EX_NOACTIVATE,TOOLTIPS_CLASSW,nullptr,WS_POPUP|TTS_ALWAYSTIP|TTS_NOPREFIX,CW_USEDEFAULT,CW_USEDEFAULT,CW_USEDEFAULT,CW_USEDEFAULT,owner,nullptr,GetModuleHandle(nullptr),nullptr);
        TOOLINFOW tool{};tool.cbSize=sizeof(tool);tool.hwnd=parent_;tool.uId=1;tool.uFlags=TTF_TRACK|TTF_ABSOLUTE|TTF_TRANSPARENT;tool.lpszText=hint_text_.data();
        if(hint_)SendMessageW(hint_,TTM_ADDTOOLW,0,reinterpret_cast<LPARAM>(&tool));
      }
      if(hint_){
        TOOLINFOW tool{};tool.cbSize=sizeof(tool);tool.hwnd=parent_;tool.uId=1;tool.lpszText=hint_text_.data();
        SendMessageW(hint_,TTM_UPDATETIPTEXTW,0,reinterpret_cast<LPARAM>(&tool));
        RECT client{};GetClientRect(parent_,&client);double scale=GetDpiForWindow(parent_)/96.0;
        SendMessageW(hint_,TTM_SETMAXTIPWIDTH,0,std::max(1L,client.right-16));
        LRESULT size=SendMessageW(hint_,TTM_GETBUBBLESIZE,0,reinterpret_cast<LPARAM>(&tool));
        int x=static_cast<int>((number(*rect,"x")+number(*rect,"width")/2)*scale)-LOWORD(size)/2;
        x=std::clamp(x,8,std::max(8,static_cast<int>(client.right)-LOWORD(size)-8));
        POINT point{x,static_cast<LONG>((number(*rect,"y")+number(*rect,"height")+8)*scale)};ClientToScreen(parent_,&point);
        SendMessageW(hint_,TTM_TRACKPOSITION,0,MAKELPARAM(point.x,point.y));
        SendMessageW(hint_,TTM_TRACKACTIVATE,TRUE,reinterpret_cast<LPARAM>(&tool));
      }
    }else if(name=="hideHeaderHint"){
      const auto* id=call.arguments()?std::get_if<int32_t>(call.arguments()):nullptr;
      const auto* id64=call.arguments()?std::get_if<int64_t>(call.arguments()):nullptr;
      if((id&&*id==hint_id_)||(id64&&*id64==hint_id_))DismissHeaderHint();
    }else if(name=="surface"){
      auto map=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;
      auto color=map?field(*map,"canvas"):nullptr;
      if(color){if(auto color64=std::get_if<int64_t>(color))background_=static_cast<uint32_t>(*color64);else if(auto color32=std::get_if<int32_t>(color))background_=static_cast<uint32_t>(*color32);}
      Microsoft::WRL::ComPtr<ICoreWebView2Controller2> themed;
      if(controller_&&SUCCEEDED(controller_.As(&themed)))themed->put_DefaultBackgroundColor({255,static_cast<BYTE>(background_>>16),static_cast<BYTE>(background_>>8),static_cast<BYTE>(background_)});
    }else if(name=="open"){
      if(capture_){capture_->Error("reader-replaced","Reader replaced");capture_.reset();}
      auto map=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;
      auto string_arg=[map](const char* key)->const std::string* { if(!map)return nullptr;auto it=map->find(EncodableValue(key));return it==map->end()?nullptr:std::get_if<std::string>(&it->second); };
      const auto* path=string_arg("publicationPath");const auto* cache=string_arg("cacheDirectory");
      if(!path||!cache){result->Error("reader-path","Publication and cache paths are required");return;}
      publication_=wide(*path);cache_directory_=wide(*cache);
      if(!std::filesystem::path(publication_).is_absolute()||!std::filesystem::path(cache_directory_).is_absolute()){result->Error("reader-path","Invalid absolute paths");return;}
      const auto* session=string_arg("session");
      if(!session||session->empty()||session->find_first_not_of("0123456789")!=std::string::npos){result->Error("reader-session","Invalid reader session");return;}
      session_=*session;
      navigation_uri_=L"https://busybooks.local/index.html?session="+wide(session_)+L"&loading="+wide(stringField(*map,"loadingQuery"));
      if(web_){web_->Navigate(navigation_uri_.c_str());result->Success();}else{if(pending_)pending_->Error("reader-replaced","Reader was replaced");pending_=std::move(result);Initialize();}return;
    }
    else if(name=="bounds"){
      auto map=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;if(!map){result->Error("reader-bounds","Invalid bounds");return;}double dpi=GetDpiForWindow(parent_)/96.0;
      bounds_={static_cast<LONG>(number(*map,"x")*dpi),static_cast<LONG>(number(*map,"y")*dpi),static_cast<LONG>((number(*map,"x")+number(*map,"width"))*dpi),static_cast<LONG>((number(*map,"y")+number(*map,"height"))*dpi)};if(controller_)controller_->put_Bounds(bounds_);
    }else if(name=="hasFocus"){
      const auto* map=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;
      const auto* value=map?field(*map,"session"):nullptr;
      const auto* session=value?std::get_if<std::string>(value):nullptr;
      if(!session){result->Error("reader-focus","Missing focus owner");return;}
      HWND owner=GetAncestor(parent_,GA_ROOT);
      result->Success(EncodableValue(*session==session_&&controller_&&visible_&&focused_&&!IsIconic(owner)&&GetForegroundWindow()==owner));return;
    }else if(name=="focusChrome"){
      const auto* map=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;
      const auto* value=map?field(*map,"session"):nullptr;
      const auto* session=value?std::get_if<std::string>(value):nullptr;
      if(!session){result->Error("reader-focus","Missing focus owner");return;}
      HWND owner=GetAncestor(parent_,GA_ROOT);
      if(*session==session_&&IsWindowVisible(parent_)&&!IsIconic(owner)&&GetForegroundWindow()==owner){focused_=false;SetFocus(parent_);}
    }else if(name=="focus"){
      const auto* map=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;
      const auto* value=map?field(*map,"session"):nullptr;
      const auto* session=value?std::get_if<std::string>(value):nullptr;
      if(!session){result->Error("reader-focus","Missing focus owner");return;}
      HWND owner=GetAncestor(parent_,GA_ROOT);
      if(*session==session_&&controller_&&visible_&&!IsIconic(owner)&&GetForegroundWindow()==owner)controller_->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
    }else if(name=="visible"){
      auto value=call.arguments()?std::get_if<bool>(call.arguments()):nullptr;visible_=value&&*value;if(!visible_){focused_=false;}if(controller_)controller_->put_IsVisible(visible_);
      // A hidden publication must not retain keyboard ownership in Notebook.
      HWND owner=GetAncestor(parent_,GA_ROOT);
      if(!visible_&&IsWindowVisible(parent_)&&!IsIconic(owner)&&GetForegroundWindow()==owner)SetFocus(parent_);
    }else if(name=="dispatch"){
      auto json=call.arguments()?std::get_if<std::string>(call.arguments()):nullptr;if(!web_||!json){result->Error("reader-unavailable","Reader is unavailable");return;}
      if(json->size()>1048576){Event("{\"type\":\"bridgeError\",\"session\":\""+session_+"\",\"direction\":\"command\",\"message\":\"Reader bridge frame limit exceeded\"}");result->Error("reader-bridge-limit","Reader bridge frame limit exceeded");return;}
      auto script=wide("window.busybooks?.dispatch("+*json+")");web_->ExecuteScript(script.c_str(),nullptr);
    }else if(name=="close"){
      if(capture_){capture_->Error("reader-closed","Reader closed");capture_.reset();}
      if(pending_){pending_->Error("reader-closed","Reader was closed");pending_.reset();}
      // A completed close must release WebView2 response/file-stream handles
      // before an explicit Move Book starts. Navigating to blank is asynchronous.
      ++initialization_generation_;initializing_=false;
      navigation_uri_=L"about:blank";navigation_id_=0;session_.clear();visible_=false;focused_=false;
      if(web_)web_->Stop();
      if(controller_)controller_->Close();
      web_.Reset();controller_.Reset();environment_.Reset();
      publication_.clear();cache_directory_.clear();
    }else{result->NotImplemented();return;}
    result->Success();
  });
  desktop_=std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger,"io.busystack.busybooks/desktop",&flutter::StandardMethodCodec::GetInstance());
  desktop_->SetMethodCallHandler([](const auto& call,auto result){if(call.method_name()!="getAccent"){result->NotImplemented();return;}DWORD color=0;BOOL opaque=FALSE;if(FAILED(DwmGetColorizationColor(&color,&opaque))){result->Error("accent-unavailable","Windows accent settings are unavailable");return;}result->Success(EncodableValue(static_cast<int64_t>(color|0xff000000)));});
  speech_=std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger,"io.busystack.busybooks/speech",&flutter::StandardMethodCodec::GetInstance());
  speech_->SetMethodCallHandler([this](const auto& call,auto result){
    if(!voice_){HRESULT hr=CoCreateInstance(CLSID_SpVoice,nullptr,CLSCTX_ALL,IID_PPV_ARGS(&voice_));if(FAILED(hr)){result->Error("speech-unavailable","Install a Windows speech voice for this language");return;}voice_->SetNotifyWindowMessage(GetAncestor(parent_,GA_ROOT),WM_APP+49,0,0);voice_->SetInterest(SPFEI(SPEI_END_INPUT_STREAM),SPFEI(SPEI_END_INPUT_STREAM));}
    auto args=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;const auto& action=call.method_name();HRESULT hr=S_OK;
    if(action=="voices"){
      Microsoft::WRL::ComPtr<IEnumSpObjectTokens> tokens;hr=SpEnumTokens(SPCAT_VOICES,nullptr,nullptr,&tokens);EncodableList list;
      if(SUCCEEDED(hr)){Microsoft::WRL::ComPtr<ISpObjectToken> token;while(tokens->Next(1,&token,nullptr)==S_OK){wchar_t* description=nullptr;if(SUCCEEDED(SpGetDescription(token.Get(),&description))){list.emplace_back(utf8(description));CoTaskMemFree(description);}token.Reset();}}
      if(FAILED(hr)){result->Error("speech-voices","Windows voice enumeration failed");return;}result->Success(EncodableValue(list));return;
    }else if(action=="speak"&&args){
      auto selected=wide(stringField(*args,"voice"));if(!selected.empty()){Microsoft::WRL::ComPtr<IEnumSpObjectTokens> tokens;SpEnumTokens(SPCAT_VOICES,nullptr,nullptr,&tokens);Microsoft::WRL::ComPtr<ISpObjectToken> token;while(tokens&&tokens->Next(1,&token,nullptr)==S_OK){wchar_t* desc=nullptr;SpGetDescription(token.Get(),&desc);if(desc&&selected==desc)voice_->SetVoice(token.Get());CoTaskMemFree(desc);token.Reset();}}
      if(speech_paused_){hr=voice_->Resume();if(SUCCEEDED(hr))speech_paused_=false;}
      if(SUCCEEDED(hr))hr=voice_->SetRate(static_cast<LONG>(std::clamp((number(*args,"speed")-1)*5,-10.0,10.0)));
      auto text=wide(stringField(*args,"text"));if(SUCCEEDED(hr))hr=voice_->Speak(text.c_str(),SPF_ASYNC|SPF_PURGEBEFORESPEAK|SPF_IS_NOT_XML,&speech_stream_);
    }else if(action=="pause"){hr=voice_->Pause();if(SUCCEEDED(hr))speech_paused_=true;}
    else if(action=="resume"){hr=voice_->Resume();if(SUCCEEDED(hr))speech_paused_=false;}
    else if(action=="stop"){speech_stream_=0;if(speech_paused_){voice_->Resume();speech_paused_=false;}hr=voice_->Speak(nullptr,SPF_PURGEBEFORESPEAK,nullptr);}else{result->NotImplemented();return;}
    if(FAILED(hr)){result->Error("speech-failed","Windows speech request failed");return;}result->Success();
  });
}
void ReaderHost::Initialize(){
  if(initializing_)return;
  initializing_=true;
  const auto generation=++initialization_generation_;
  HRESULT hr=CreateCoreWebView2EnvironmentWithOptions(nullptr,profile_.c_str(),nullptr,Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([this,alive=alive_,generation](HRESULT result,ICoreWebView2Environment* env)->HRESULT{
    if(!*alive||generation!=initialization_generation_)return S_OK;
    if(FAILED(result)||!env){initializing_=false;if(pending_){pending_->Error("webview-runtime","Install the Microsoft Edge WebView2 Runtime (Evergreen standalone installer)");pending_.reset();}return S_OK;}environment_=env;
    HRESULT controller_result=env->CreateCoreWebView2Controller(parent_,Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([this,alive=alive_,generation](HRESULT code,ICoreWebView2Controller* controller)->HRESULT{
      if(!*alive||generation!=initialization_generation_){if(controller)controller->Close();return S_OK;}
      initializing_=false;
      if(FAILED(code)||!controller){if(pending_){pending_->Error("webview-create","WebView2 controller creation failed");pending_.reset();}return S_OK;}
      controller_=controller;
      Microsoft::WRL::ComPtr<ICoreWebView2Controller2> themed;
      if(SUCCEEDED(controller_.As(&themed)))themed->put_DefaultBackgroundColor({255,static_cast<BYTE>(background_>>16),static_cast<BYTE>(background_>>8),static_cast<BYTE>(background_)});
      controller_->get_CoreWebView2(&web_);controller_->put_Bounds(bounds_);controller_->put_IsVisible(visible_);
      Microsoft::WRL::ComPtr<ICoreWebView2Settings> settings;web_->get_Settings(&settings);settings->put_AreDevToolsEnabled(FALSE);settings->put_AreDefaultContextMenusEnabled(FALSE);settings->put_IsStatusBarEnabled(FALSE);
      EventRegistrationToken token;
      controller_->add_GotFocus(Callback<ICoreWebView2FocusChangedEventHandler>([this,alive=alive_,generation](ICoreWebView2Controller*,IUnknown*)->HRESULT{if(*alive&&generation==initialization_generation_)focused_=true;return S_OK;}).Get(),&token);
      controller_->add_LostFocus(Callback<ICoreWebView2FocusChangedEventHandler>([this,alive=alive_,generation](ICoreWebView2Controller*,IUnknown*)->HRESULT{if(*alive&&generation==initialization_generation_)focused_=false;return S_OK;}).Get(),&token);
      web_->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>([this,alive=alive_,generation](ICoreWebView2*,ICoreWebView2WebMessageReceivedEventArgs* args)->HRESULT{if(!*alive||generation!=initialization_generation_)return S_OK;wchar_t* value=nullptr;if(SUCCEEDED(args->TryGetWebMessageAsString(&value))){Event(utf8(value));CoTaskMemFree(value);}return S_OK;}).Get(),&token);
      web_->AddWebResourceRequestedFilter(L"*",COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
      web_->add_WebResourceRequested(Callback<ICoreWebView2WebResourceRequestedEventHandler>([this,alive=alive_,generation](ICoreWebView2*,ICoreWebView2WebResourceRequestedEventArgs* args)->HRESULT{
        if(!*alive||generation!=initialization_generation_)return S_OK;
        Microsoft::WRL::ComPtr<ICoreWebView2WebResourceRequest> request;args->get_Request(&request);wchar_t* raw=nullptr;request->get_Uri(&raw);std::wstring uri=raw?raw:L"";CoTaskMemFree(raw);
        std::wstring prefix=L"https://busybooks.local/",path,mime=L"application/octet-stream";bool allowed=uri.rfind(prefix,0)==0;
        if(allowed){auto rel=uri.substr(prefix.size());auto query=rel.find_first_of(L"?#");if(query!=std::wstring::npos)rel.resize(query);std::vector<wchar_t> decoded(rel.begin(),rel.end());decoded.push_back(0);DWORD length=static_cast<DWORD>(decoded.size());if(FAILED(UrlUnescapeW(decoded.data(),nullptr,&length,URL_UNESCAPE_INPLACE)))allowed=false;rel=decoded.data();if(rel.find(L"..")!=std::wstring::npos||rel.find(L':')!=std::wstring::npos||rel.find(L'\\')!=std::wstring::npos||(!rel.empty()&&rel[0]==L'/'))allowed=false;
          if(rel==L"publication")path=publication_;
          else if(rel==L"book-index"||rel.rfind(L"book/",0)==0){if(rel!=L"book-index"){auto resource=rel.substr(5);if(resource.size()!=64||!std::all_of(resource.begin(),resource.end(),[](wchar_t c){return (c>=L'0'&&c<=L'9')||(c>=L'a'&&c<=L'f');}))allowed=false;}path=rel==L"book-index"?cache_directory_+L".json":(std::filesystem::path(cache_directory_)/rel.substr(5)).wstring();}
          else path=(std::filesystem::path(assets_)/rel).wstring();auto extension=std::filesystem::path(path).extension().wstring();if(extension==L".html")mime=L"text/html";else if(extension==L".js"||extension==L".mjs")mime=L"text/javascript";else if(extension==L".css")mime=L"text/css";else if(extension==L".wasm")mime=L"application/wasm";
        }
        Microsoft::WRL::ComPtr<IStream> stream;HRESULT loaded=allowed?SHCreateStreamOnFileEx(path.c_str(),STGM_READ|STGM_SHARE_DENY_WRITE,FILE_ATTRIBUTE_NORMAL,FALSE,nullptr,&stream):E_ACCESSDENIED;
        Microsoft::WRL::ComPtr<ICoreWebView2WebResourceResponse> response;std::wstring headers=L"Content-Type: "+mime+L"\r\nCache-Control: no-store";
        environment_->CreateWebResourceResponse(stream.Get(),SUCCEEDED(loaded)?200:403,SUCCEEDED(loaded)?L"OK":L"Blocked",headers.c_str(),&response);args->put_Response(response.Get());return S_OK;
      }).Get(),&token);
      web_->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>([this,alive=alive_,generation](ICoreWebView2*,ICoreWebView2NavigationStartingEventArgs* args)->HRESULT{if(!*alive||generation!=initialization_generation_)return S_OK;wchar_t* uri=nullptr;args->get_Uri(&uri);std::wstring value=uri?uri:L"";CoTaskMemFree(uri);if(value.rfind(L"https://busybooks.local/",0)!=0&&value.rfind(L"blob:",0)!=0&&value!=L"about:blank")args->put_Cancel(TRUE);if(value==navigation_uri_)args->get_NavigationId(&navigation_id_);return S_OK;}).Get(),&token);
      web_->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>([this,alive=alive_,generation](ICoreWebView2*,ICoreWebView2NavigationCompletedEventArgs* args)->HRESULT{
        if(!*alive||generation!=initialization_generation_)return S_OK;
        UINT64 id=0;BOOL success=FALSE;args->get_NavigationId(&id);args->get_IsSuccess(&success);
        if(!success&&id==navigation_id_&&!session_.empty()){
          COREWEBVIEW2_WEB_ERROR_STATUS status;args->get_WebErrorStatus(&status);
          if(status!=COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED)Event("{\"type\":\"error\",\"session\":\""+session_+"\",\"message\":\"Reader navigation failed ("+std::to_string(status)+"). Reopen the book.\"}");
        }return S_OK;
      }).Get(),&token);
      web_->add_ProcessFailed(Callback<ICoreWebView2ProcessFailedEventHandler>([this,alive=alive_,generation](ICoreWebView2*,ICoreWebView2ProcessFailedEventArgs* args)->HRESULT{
        if(!*alive||generation!=initialization_generation_)return S_OK;
        COREWEBVIEW2_PROCESS_FAILED_KIND kind;args->get_ProcessFailedKind(&kind);
        if(!session_.empty()&&(kind==COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED||kind==COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED||kind==COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE))Event("{\"type\":\"error\",\"session\":\""+session_+"\",\"message\":\"Reader process failed ("+std::to_string(kind)+"). Reopen the book.\"}");
        return S_OK;
      }).Get(),&token);
      web_->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>([](ICoreWebView2*,ICoreWebView2NewWindowRequestedEventArgs* args)->HRESULT{args->put_Handled(TRUE);return S_OK;}).Get(),&token);
      web_->Navigate(pending_?navigation_uri_.c_str():L"about:blank");if(pending_){pending_->Success();pending_.reset();}return S_OK;
    }).Get());
    if(FAILED(controller_result)){initializing_=false;if(pending_){pending_->Error("webview-create","WebView2 controller creation failed");pending_.reset();}}
    return S_OK;
  }).Get());
  if(FAILED(hr)){initializing_=false;if(pending_){pending_->Error("webview-runtime","WebView2 Runtime is not available");pending_.reset();}}
}
void ReaderHost::Event(const std::string& json,std::size_t limit){
  if(json.size()>limit){Event("{\"type\":\"bridgeError\",\"session\":\""+session_+"\",\"direction\":\"event\",\"message\":\"Reader bridge frame limit exceeded\"}");return;}
  channel_->InvokeMethod("event",std::make_unique<EncodableValue>(json));
}
void ReaderHost::FileOpened(const wchar_t* path){if(!path||!*path)return;std::wstring value(path);EncodableList paths;size_t start=0;while(start<value.size()){auto end=value.find(L'\n',start);auto file=value.substr(start,end==std::wstring::npos?std::wstring::npos:end-start);if(!file.empty()){if(input_ready_)paths.emplace_back(utf8(file.c_str()));else pending_files_.push_back(utf8(file.c_str()));}if(end==std::wstring::npos)break;start=end+1;}if(!paths.empty())input_->InvokeMethod("filesOpened",std::make_unique<EncodableValue>(paths));}
void ReaderHost::FilesDropped(HDROP drop){EncodableList paths;UINT count=DragQueryFileW(drop,0xffffffff,nullptr,0);for(UINT i=0;i<count;i++){UINT n=DragQueryFileW(drop,i,nullptr,0);std::wstring path(n+1,0);DragQueryFileW(drop,i,path.data(),n+1);if(input_ready_)paths.emplace_back(utf8(path.c_str()));else pending_files_.push_back(utf8(path.c_str()));}DragFinish(drop);if(!paths.empty())input_->InvokeMethod("assetFilesDropped",std::make_unique<EncodableValue>(paths));}
void ReaderHost::AppearanceChanged(){DWORD color=0;BOOL opaque=FALSE;if(SUCCEEDED(DwmGetColorizationColor(&color,&opaque)))desktop_->InvokeMethod("accentChanged",std::make_unique<EncodableValue>(static_cast<int64_t>(color|0xff000000)));}
void ReaderHost::SpeechEvents(){if(!voice_)return;SPEVENT event{};ULONG fetched=0;while(voice_->GetEvents(1,&event,&fetched)==S_OK&&fetched){if(event.eEventId==SPEI_END_INPUT_STREAM&&event.ulStreamNum==speech_stream_)speech_->InvokeMethod("event",std::make_unique<EncodableValue>("stopped"));SpClearEvent(&event);}}
ReaderHost::~ReaderHost(){*alive_=false;if(capture_){capture_->Error("reader-closed","Reader closed");capture_.reset();}if(hint_)DestroyWindow(hint_);menus_.reset();input_->SetMethodCallHandler(nullptr);desktop_->SetMethodCallHandler(nullptr);channel_->SetMethodCallHandler(nullptr);speech_->SetMethodCallHandler(nullptr);if(voice_)voice_->Speak(nullptr,SPF_PURGEBEFORESPEAK,nullptr);if(controller_)controller_->Close();web_.Reset();controller_.Reset();environment_.Reset();std::error_code error;std::filesystem::remove_all(profile_,error);}

void ReaderHost::DismissHeaderHint(){if(hint_){TOOLINFOW tool{};tool.cbSize=sizeof(tool);tool.hwnd=parent_;tool.uId=1;SendMessageW(hint_,TTM_TRACKACTIVATE,FALSE,reinterpret_cast<LPARAM>(&tool));}}
