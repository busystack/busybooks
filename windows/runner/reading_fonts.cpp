#include "../../native/reading_fonts.h"
#include <windows.h>
#include <dwrite_3.h>
#include <d2d1.h>
#include <wincodec.h>
#include <shlwapi.h>
#include <wrl.h>
#include <algorithm>
#include <chrono>
#include <mutex>
#include <stdexcept>
#include <unordered_set>

namespace reading_fonts {
namespace {
using Microsoft::WRL::ComPtr;
std::mutex mutex;
std::vector<Family> catalogue;
bool loaded = false;
auto refreshed = std::chrono::steady_clock::time_point{};
void check(HRESULT hr) { if (FAILED(hr)) throw std::runtime_error("Windows local font operation failed"); }
std::wstring wide(const std::string& value) {
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (!count) throw std::runtime_error("Invalid font text");
  std::wstring result(count, 0); check(MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), count) ? S_OK : E_INVALIDARG); return result;
}
std::string utf8(const std::wstring& value) {
  int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (!count) return {};
  std::string result(count, 0); WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), count, nullptr, nullptr); return result;
}
struct Apartment {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  Apartment() { check(hr); }
  ~Apartment() { if (SUCCEEDED(hr)) CoUninitialize(); }
};
struct Fonts {
  ComPtr<IDWriteFactory3> factory;
  ComPtr<IDWriteFontCollection1> collection;
  explicit Fonts(bool refresh = false) {
    check(DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED, __uuidof(IDWriteFactory3), reinterpret_cast<IUnknown**>(factory.GetAddressOf())));
    // FALSE explicitly excludes downloadable/cloud-only fonts. Never enqueue a
    // font download. Windows 10 is already required by the native reader host.
    check(factory->GetSystemFontCollection(FALSE, &collection, refresh ? TRUE : FALSE));
  }
};
std::wstring localized(IDWriteLocalizedStrings* names, const wchar_t* locale) {
  UINT32 index = 0; BOOL exists = FALSE;
  check(names->FindLocaleName(locale, &index, &exists));
  if (!exists) { check(names->FindLocaleName(L"en-us", &index, &exists)); if (!exists) index = 0; }
  UINT32 length = 0; check(names->GetStringLength(index, &length));
  std::wstring result(length + 1, 0); check(names->GetString(index, result.data(), length + 1)); result.resize(length); return result;
}
void discover(bool refresh) {
  if (loaded && !refresh && std::chrono::steady_clock::now() - refreshed < std::chrono::minutes(1)) return;
  Fonts fonts(refresh); std::vector<Family> result; std::unordered_set<std::string> seen;
  wchar_t locale[LOCALE_NAME_MAX_LENGTH] = L"en-us"; GetUserDefaultLocaleName(locale, LOCALE_NAME_MAX_LENGTH);
  for (UINT32 i = 0; i < fonts.collection->GetFontFamilyCount(); ++i) {
    ComPtr<IDWriteFontFamily> family; check(fonts.collection->GetFontFamily(i, &family));
    ComPtr<IDWriteLocalizedStrings> names; check(family->GetFamilyNames(&names));
    const auto id = utf8(localized(names.Get(), L"en-us")), label = utf8(localized(names.Get(), locale));
    // DirectWrite's family groups localized names/faces. Keep distinct families
    // even when their localized display names happen to match.
    if (ValidName(id) && ValidName(label) && seen.insert(id).second) result.push_back({id, label});
  }
  std::sort(result.begin(), result.end(), [](const Family& a, const Family& b) { return a.label < b.label; });
  catalogue = std::move(result); loaded = true; refreshed = std::chrono::steady_clock::now();
}
std::string identity(const std::string& name, bool generic) {
  if (!ValidName(name)) throw std::runtime_error("Invalid font family");
  if (generic) {
    if (name == "serif") return "Times New Roman";
    if (name == "sans-serif") return "Arial";
    if (name == "monospace") return "Consolas";
    throw std::runtime_error("Invalid generic font");
  }
  discover(false);
  for (const auto& f : catalogue) if (_wcsicmp(wide(f.id).c_str(), wide(name).c_str()) == 0) return f.id;
  throw std::runtime_error("Font is unavailable");
}
ComPtr<IDWriteFontFamily> family(Fonts& fonts, const std::string& name) {
  UINT32 index = 0; BOOL exists = FALSE; check(fonts.collection->FindFamilyName(wide(name).c_str(), &index, &exists));
  if (!exists) throw std::runtime_error("Font is unavailable");
  ComPtr<IDWriteFontFamily> result; check(fonts.collection->GetFontFamily(index, &result)); return result;
}
D2D1_COLOR_F rgb(uint32_t c) { return D2D1::ColorF(((c >> 16) & 255) / 255.f, ((c >> 8) & 255) / 255.f, (c & 255) / 255.f); }
}
bool ValidName(const std::string& value) {
  if (value.empty()) return false;
  try {
    const auto name = wide(value);
    if (name.size() > 256 || iswspace(name.front()) || iswspace(name.back())) return false;
    for (auto ch : name) if (ch < 32 || (ch >= 127 && ch <= 159) || ch == 0xfffd) return false;
    return true;
  } catch (const std::exception&) { return false; }
}
std::vector<Family> Discover(bool refresh) { Apartment apartment; std::lock_guard<std::mutex> lock(mutex); discover(refresh); return catalogue; }
Resolution Resolve(const std::string& requested, bool generic) {
  Apartment apartment; std::lock_guard<std::mutex> lock(mutex);
  const auto name = identity(requested, generic); Fonts fonts; auto group = family(fonts, name);
  Resolution result{name, {}};
  for (int weight = 100; weight <= 900; weight += 100) for (bool italic : {false, true}) {
    ComPtr<IDWriteFont> font; check(group->GetFirstMatchingFont(static_cast<DWRITE_FONT_WEIGHT>(weight), DWRITE_FONT_STRETCH_NORMAL, italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL, &font));
    const auto simulations = font->GetSimulations();
    // Simulated faces are not installed faces. Leave them absent so the browser
    // can synthesize from actual sources rather than declaring false metadata.
    if (simulations != DWRITE_FONT_SIMULATIONS_NONE) continue;
    Face face{{}, static_cast<int>(font->GetWeight()), font->GetStyle() != DWRITE_FONT_STYLE_NORMAL};
    for (auto kind : {DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME, DWRITE_INFORMATIONAL_STRING_FULL_NAME}) {
      ComPtr<IDWriteLocalizedStrings> names; BOOL exists = FALSE;
      check(font->GetInformationalStrings(kind, &names, &exists));
      if (exists) { const auto source = utf8(localized(names.Get(), L"en-us")); if (ValidName(source) && std::find(face.sources.begin(), face.sources.end(), source) == face.sources.end()) face.sources.push_back(source); }
    }
    if (face.sources.empty()) throw std::runtime_error("Local font has no usable face identity");
    result.faces.push_back(std::move(face));
  }
  return result;
}
std::vector<uint8_t> Preview(const std::string& requested, bool generic, const Sample& sample) {
  Apartment apartment; std::lock_guard<std::mutex> lock(mutex);
  const auto name = identity(requested, generic); Fonts fonts; family(fonts, name);
  const UINT width = static_cast<UINT>(std::clamp(sample.width, 80, 800)), height = static_cast<UINT>(std::clamp(sample.height, 60, 240));
  const double scale = std::clamp(sample.scale, 1., 3.);
  ComPtr<IWICImagingFactory> wic; check(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic)));
  ComPtr<IWICBitmap> bitmap; check(wic->CreateBitmap(static_cast<UINT>(width * scale), static_cast<UINT>(height * scale), GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad, &bitmap));
  ComPtr<ID2D1Factory> d2d; check(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, d2d.GetAddressOf()));
  ComPtr<ID2D1RenderTarget> target;
  check(d2d->CreateWicBitmapRenderTarget(bitmap.Get(), D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), static_cast<float>(96 * scale), static_cast<float>(96 * scale)), &target));
  ComPtr<ID2D1SolidColorBrush> brush; check(target->CreateSolidColorBrush(rgb(sample.foreground), &brush));
  target->BeginDraw(); target->Clear(rgb(sample.background));
  const std::string lines[] = {sample.prose, sample.bold, sample.italic};
  const int base_weight = std::clamp(sample.weight, 300, 700), bold_weight = base_weight < 350 ? 400 : base_weight < 550 ? 700 : 900;
  FLOAT y = 8;
  for (int i = 0; i < 3; ++i) {
    const auto text = lines[i].empty() ? std::wstring{} : wide(lines[i]);
    ComPtr<IDWriteTextFormat> format;
    check(fonts.factory->CreateTextFormat(wide(name).c_str(), fonts.collection.Get(), static_cast<DWRITE_FONT_WEIGHT>(i == 1 ? bold_weight : base_weight), i == 2 ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, static_cast<FLOAT>(std::clamp(sample.size, 14., 28.)), L"", &format));
    check(format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP));
    ComPtr<IDWriteTextLayout> layout; check(fonts.factory->CreateTextLayout(text.c_str(), static_cast<UINT32>(text.size()), format.Get(), static_cast<FLOAT>(width - 16), static_cast<FLOAT>(height), &layout));
    target->DrawTextLayout(D2D1::Point2F(8, y), layout.Get(), brush.Get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);
    DWRITE_TEXT_METRICS metrics{}; check(layout->GetMetrics(&metrics)); y += std::min(std::max(metrics.height * static_cast<FLOAT>(std::clamp(sample.line, 1., 1.6)), 28.f), (height - 16) / 3.f);
  }
  check(target->EndDraw());
  ComPtr<IStream> stream; stream.Attach(SHCreateMemStream(nullptr, 0)); if (!stream) throw std::runtime_error("Font preview memory is unavailable");
  ComPtr<IWICBitmapEncoder> encoder; check(wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)); check(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache));
  ComPtr<IWICBitmapFrameEncode> frame; check(encoder->CreateNewFrame(&frame, nullptr)); check(frame->Initialize(nullptr));
  check(frame->SetSize(static_cast<UINT>(width * scale), static_cast<UINT>(height * scale)));
  WICPixelFormatGUID pixel = GUID_WICPixelFormat32bppBGRA; check(frame->SetPixelFormat(&pixel)); check(frame->WriteSource(bitmap.Get(), nullptr)); check(frame->Commit()); check(encoder->Commit());
  STATSTG stat{}; check(stream->Stat(&stat, STATFLAG_NONAME)); if (stat.cbSize.QuadPart > 4 * 1024 * 1024) throw std::runtime_error("Font preview exceeds its limit");
  LARGE_INTEGER start{}; check(stream->Seek(start, STREAM_SEEK_SET, nullptr));
  std::vector<uint8_t> bytes(static_cast<size_t>(stat.cbSize.QuadPart)); ULONG read = 0; check(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read)); if (read != bytes.size()) throw std::runtime_error("Incomplete font preview"); return bytes;
}
}
