// Host menus use the same serialized entries/session contract as BusyMark's GTK
// host. The book child remains visible; Flutter retains actions and keybindings.
#include "native_menu_host.h"
#include <flutter/standard_method_codec.h>
#include <cmath>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>
using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
namespace {
constexpr UINT kPresentMenu = WM_APP + 90;
const EncodableValue* Field(const EncodableMap& map, const char* key) {
  auto found=map.find(EncodableValue(key));return found==map.end()?nullptr:&found->second;
}
std::string Text(const EncodableMap& map,const char* key) {
  auto value=Field(map,key);auto text=value?std::get_if<std::string>(value):nullptr;return text?*text:"";
}
bool Flag(const EncodableMap& map,const char* key,bool fallback=false) {
  auto value=Field(map,key);auto flag=value?std::get_if<bool>(value):nullptr;return flag?*flag:fallback;
}
int64_t Integer(const EncodableMap& map,const char* key) {
  auto value=Field(map,key);if(!value)return 0;
  if(auto n=std::get_if<int64_t>(value))return *n;
  if(auto n=std::get_if<int32_t>(value))return *n;return 0;
}
double Number(const EncodableMap& map,const char* key) {
  auto value=Field(map,key);if(!value)return NAN;
  if(auto n=std::get_if<double>(value))return *n;
  return static_cast<double>(Integer(map,key));
}
std::wstring Label(const std::string& text) {
  int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0);
  std::wstring result(size,0);MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),result.data(),size);
  for(size_t at=0;(at=result.find(L'&',at))!=std::wstring::npos;at+=2)result.insert(at,1,L'&');
  return result;
}
// Own the small view-icon masks for exactly the lifetime of their native menu.
struct MenuBitmaps {
  std::vector<HBITMAP> handles;
  size_t mask_bytes = 0;
  ~MenuBitmaps() { for (auto bitmap : handles) DeleteObject(bitmap); }
};
HBITMAP ViewBitmap(const std::vector<uint8_t>& alpha, int size, bool enabled) {
  BITMAPINFO info{};
  info.bmiHeader.biSize = static_cast<DWORD>(sizeof(BITMAPINFOHEADER));
  info.bmiHeader.biWidth = size;
  info.bmiHeader.biHeight = -size;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (!bitmap || !pixels) { if (bitmap) DeleteObject(bitmap); return nullptr; }
  const COLORREF color = GetSysColor(enabled ? COLOR_MENUTEXT : COLOR_GRAYTEXT);
  auto* output = static_cast<uint8_t*>(pixels);
  for (size_t i = 0; i < alpha.size(); ++i) {
    output[i*4] = static_cast<uint8_t>((GetBValue(color)*alpha[i]+127)/255);
    output[i*4+1] = static_cast<uint8_t>((GetGValue(color)*alpha[i]+127)/255);
    output[i*4+2] = static_cast<uint8_t>((GetRValue(color)*alpha[i]+127)/255);
    output[i*4+3] = alpha[i];
  }
  return bitmap;
}
HMENU Build(const EncodableList& entries,UINT& position,int depth,MenuBitmaps& bitmaps) {
  if(depth>16)return nullptr;
  HMENU menu=CreatePopupMenu();if(!menu)return nullptr;
  for(const auto& value:entries){
    auto item=std::get_if<EncodableMap>(&value);
    if(!item||position>=10000){DestroyMenu(menu);return nullptr;}
    const UINT id=++position; // Same preorder, including separators and headings.
    MENUITEMINFOW info{};info.cbSize=static_cast<UINT>(sizeof(MENUITEMINFOW));
    info.fMask=MIIM_FTYPE|MIIM_STATE|MIIM_ID;info.wID=id;
    info.fType=Flag(*item,"separator")?MFT_SEPARATOR:MFT_STRING;
    if(Flag(*item,"mutuallyExclusive"))info.fType|=MFT_RADIOCHECK;
    info.fState=Flag(*item,"enabled",true)?MFS_ENABLED:MFS_DISABLED;
    if(Flag(*item,"checkable")&&Flag(*item,"selected"))info.fState|=MFS_CHECKED;
    auto label=Label(Text(*item,"label"));const auto shortcut=Text(*item,"shortcut");
    if(!shortcut.empty())label+=L"\t"+Label(shortcut);
    if(label.size()>8192){DestroyMenu(menu);return nullptr;}
    info.fMask|=MIIM_STRING;info.dwTypeData=label.data();
    if (auto mask_value = Field(*item, "iconMask")) {
      const auto* mask = std::get_if<std::vector<uint8_t>>(mask_value);
      const auto size = Integer(*item, "iconSize");
      if (!mask || size < 16 || size > 64 || mask->size() != static_cast<size_t>(size*size) ||
          bitmaps.mask_bytes + mask->size() > 65536) { DestroyMenu(menu); return nullptr; }
      HBITMAP bitmap = ViewBitmap(*mask, static_cast<int>(size), Flag(*item, "enabled", true));
      if (!bitmap) { DestroyMenu(menu); return nullptr; }
      bitmaps.handles.push_back(bitmap);
      bitmaps.mask_bytes += mask->size();
      info.fMask |= MIIM_BITMAP;
      info.hbmpItem = bitmap;
    }
    auto children=Field(*item,"children");
    if(children){
      auto list=std::get_if<EncodableList>(children);
      info.hSubMenu=list?Build(*list,position,depth+1,bitmaps):nullptr;
      if(!info.hSubMenu){DestroyMenu(menu);return nullptr;}info.fMask|=MIIM_SUBMENU;
    }
    if(!InsertMenuItemW(menu,static_cast<UINT>(GetMenuItemCount(menu)),TRUE,&info)){
      if(info.hSubMenu)DestroyMenu(info.hSubMenu);DestroyMenu(menu);return nullptr;
    }
  }
  return menu;
}
}
struct NativeMenuHost::Request {
  int64_t session=0;
  HMENU menu=nullptr;
  MenuBitmaps bitmaps;
  POINT point{};
  UINT flags=0;
  bool focus_first=false;
  std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
  ~Request(){if(menu)DestroyMenu(menu);}
  void Cancel(){if(result){result->Success();result.reset();}}
};
NativeMenuHost::NativeMenuHost(HWND anchor,flutter::BinaryMessenger* messenger):anchor_(anchor){
  WNDCLASSW wc{};wc.lpfnWndProc=Procedure;wc.hInstance=GetModuleHandleW(nullptr);wc.lpszClassName=L"BusyBooksMenuMessages";
  RegisterClassW(&wc);
  messages_=CreateWindowW(wc.lpszClassName,L"",0,0,0,0,0,HWND_MESSAGE,nullptr,wc.hInstance,this);
  channel_=std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger,"busybooks/native_menus",&flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call,auto result){
    auto map=call.arguments()?std::get_if<EncodableMap>(call.arguments()):nullptr;
    const auto session=map?Integer(*map,"sessionId"):0;
    if(!map||session<=0){result->Error("bad-arguments","A positive menu session is required");return;}
    if(call.method_name()=="dismiss"){
      bool dismissed=false;
      if(pending_&&pending_->session==session){pending_->Cancel();pending_.reset();dismissed=true;}
      if(active_&&active_->session==session){EndMenu();dismissed=true;}
      result->Success(EncodableValue(dismissed));return;
    }
    if(call.method_name()!="show"){result->NotImplemented();return;}
    auto entries=Field(*map,"entries"),anchor_value=Field(*map,"anchor");
    auto list=entries?std::get_if<EncodableList>(entries):nullptr;
    auto rect=anchor_value?std::get_if<EncodableMap>(anchor_value):nullptr;
    if(!messages_||!IsWindow(anchor_)){result->Error("unavailable","The menu window is unavailable");return;}
    if(!list||!rect){result->Error("bad-arguments","Menu entries and an anchor are required");return;}
    const double x=Number(*rect,"x"),y=Number(*rect,"y"),width=Number(*rect,"width"),height=Number(*rect,"height");
    const auto preferred=Text(*map,"preferredPosition");
    if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(width)||!std::isfinite(height)||width<0||height<0||std::abs(x)>100000||std::abs(y)>100000||width>100000||height>100000||(preferred!="top"&&preferred!="bottom")){
      result->Error("bad-arguments","Invalid menu geometry or preferred position");return;
    }
    auto request=std::make_shared<Request>();
    UINT count=0;HMENU menu=Build(*list,count,0,request->bitmaps);
    if(!menu){result->Error("bad-arguments","Invalid menu definition");return;}
    const double scale=GetDpiForWindow(anchor_)/96.0;const bool rtl=Text(*map,"textDirection")=="rtl",above=preferred=="top";
    request->session=session;request->menu=menu;
    request->point={static_cast<LONG>((x+(rtl?width:0))*scale),static_cast<LONG>((y+(above?0:height))*scale)};
    ClientToScreen(anchor_,&request->point);
    request->flags=TPM_RETURNCMD|TPM_NONOTIFY|TPM_RIGHTBUTTON|(rtl?TPM_RIGHTALIGN|TPM_LAYOUTRTL:TPM_LEFTALIGN)|(above?TPM_BOTTOMALIGN:TPM_TOPALIGN);
    request->focus_first=Flag(*map,"focusFirst");request->result=std::move(result);
    if(pending_)pending_->Cancel();pending_=std::move(request);
    if(active_)EndMenu();PostMessageW(messages_,kPresentMenu,0,0);
  });
}
NativeMenuHost::~NativeMenuHost(){
  *alive_=false;channel_->SetMethodCallHandler(nullptr);
  if(pending_)pending_->Cancel();if(active_){active_->Cancel();EndMenu();}
  if(messages_)DestroyWindow(messages_);
}
void NativeMenuHost::Present(){
  if(active_||!pending_)return;
  auto request=std::move(pending_);auto alive=alive_;
  HWND owner=GetAncestor(anchor_,GA_ROOT);
  if(IsIconic(owner)||GetForegroundWindow()!=owner){request->Cancel();return;}
  active_=request;
  if(request->focus_first)PostMessageW(owner,WM_KEYDOWN,VK_DOWN,0);
  const UINT chosen=static_cast<UINT>(TrackPopupMenuEx(request->menu,request->flags,request->point.x,request->point.y,owner,nullptr));
  if(!*alive)return;
  active_.reset();
  if(request->result){
    if(chosen)request->result->Success(EncodableValue(static_cast<int32_t>(chosen-1)));else request->result->Success();
    request->result.reset();
  }
  PostMessageW(owner,WM_NULL,0,0);
  if(pending_)PostMessageW(messages_,kPresentMenu,0,0);
}
LRESULT CALLBACK NativeMenuHost::Procedure(HWND hwnd,UINT message,WPARAM wparam,LPARAM lparam){
  auto* self=reinterpret_cast<NativeMenuHost*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
  if(message==WM_NCCREATE){self=static_cast<NativeMenuHost*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));}
  if(self&&message==kPresentMenu){self->Present();return 0;}
  return DefWindowProcW(hwnd,message,wparam,lparam);
}
