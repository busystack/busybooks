#include "../../native/reading_fonts.h"
#include <pango/pangocairo.h>
#include <pango/pangofc-font.h>
#include <pango/pangofc-fontmap.h>
#include <fontconfig/fontconfig.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <unordered_set>

namespace reading_fonts {
namespace {
std::mutex mutex;
std::vector<Family> catalogue;
bool loaded = false;
auto refreshed = std::chrono::steady_clock::time_point{};
struct Unref { void operator()(gpointer object) const { if (object) g_object_unref(object); } };
template<class T> using Owned = std::unique_ptr<T, Unref>;
std::string folded(const std::string& name) {
  g_autofree char* value = g_utf8_casefold(name.c_str(), -1);
  return value ? value : "";
}
Owned<PangoFontMap> font_map() {
  auto* map = pango_cairo_font_map_new();
  if (!map) throw std::runtime_error("Local font map is unavailable");
  return Owned<PangoFontMap>(map);
}
void discover(bool refresh) {
  if (loaded && !refresh && std::chrono::steady_clock::now() - refreshed < std::chrono::minutes(1)) return;
  auto map = font_map();
  PangoFontFamily** families = nullptr; int count = 0;
  pango_font_map_list_families(map.get(), &families, &count);
  std::unique_ptr<PangoFontFamily*, decltype(&g_free)> release(families, g_free);
  std::vector<Family> result;
  std::unordered_set<std::string> seen;
  for (int i = 0; i < count; ++i) {
    const std::string name = pango_font_family_get_name(families[i]);
    const auto key = folded(name);
    // Pango includes synthetic generic families in addition to installed ones.
    if (!ValidName(name) || key == "serif" || key == "sans" || key == "sans-serif" || key == "monospace" || key == "system-ui") continue;
    if (seen.insert(key).second) result.push_back({name, name});
  }
  std::sort(result.begin(), result.end(), [](const Family& a, const Family& b) { return folded(a.label) < folded(b.label); });
  catalogue = std::move(result); loaded = true; refreshed = std::chrono::steady_clock::now();
}
std::string identity(const std::string& name, bool generic) {
  if (!ValidName(name)) throw std::runtime_error("Invalid font family");
  if (generic) {
    if (name == "serif" || name == "sans-serif" || name == "monospace") return name;
    throw std::runtime_error("Invalid generic font");
  }
  discover(false);
  for (const auto& f : catalogue) if (folded(f.id) == folded(name)) return f.id;
  throw std::runtime_error("Font is unavailable");
}
std::string pattern_string(FcPattern* pattern, const char* field) {
  FcChar8* value = nullptr;
  return FcPatternGetString(pattern, field, 0, &value) == FcResultMatch ? reinterpret_cast<char*>(value) : "";
}
constexpr const char* literal_alias = "busybooks-native-reading-family";
void literal_family(PangoFontMap* map, const std::string& name) {
  // Pango descriptions interpret commas as a family list. Substitute our private
  // token through Fontconfig's *string* API so literal commas/quotes/backslashes
  // never become list syntax. No font files or global config are modified.
  pango_fc_font_map_set_default_substitute(PANGO_FC_FONT_MAP(map), +[](FcPattern* pattern, gpointer data) {
    bool ours = false;
    for (int i = 0; ; ++i) {
      FcChar8* family = nullptr;
      if (FcPatternGetString(pattern, FC_FAMILY, i, &family) != FcResultMatch) break;
      if (std::string(reinterpret_cast<char*>(family)) == literal_alias) ours = true;
    }
    if (ours) {
      FcPatternDel(pattern, FC_FAMILY);
      FcPatternAddString(pattern, FC_FAMILY, reinterpret_cast<const FcChar8*>(static_cast<std::string*>(data)->c_str()));
    }
  }, new std::string(name), +[](gpointer data) { delete static_cast<std::string*>(data); });
}
struct Match {
  Owned<PangoFont> font;
  std::string family;
  Face face;
};
Match match(PangoFontMap* map, PangoContext* context, const std::string& name, bool generic, int weight, bool italic) {
  std::unique_ptr<PangoFontDescription, decltype(&pango_font_description_free)> desc(pango_font_description_new(), pango_font_description_free);
  pango_font_description_set_family(desc.get(), generic ? (name == "sans-serif" ? "sans" : name.c_str()) : literal_alias);
  pango_font_description_set_weight(desc.get(), static_cast<PangoWeight>(weight));
  pango_font_description_set_style(desc.get(), italic ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL);
  pango_font_description_set_absolute_size(desc.get(), 20 * PANGO_SCALE);
  Owned<PangoFont> font(pango_font_map_load_font(map, context, desc.get()));
  if (!font || !PANGO_IS_FC_FONT(font.get())) throw std::runtime_error("Local font cannot be resolved");
  auto* pattern = pango_fc_font_get_pattern(PANGO_FC_FONT(font.get()));
  bool exact = generic;
  for (int i = 0; !exact; ++i) {
    FcChar8* family = nullptr;
    if (FcPatternGetString(pattern, FC_FAMILY, i, &family) != FcResultMatch) break;
    exact = folded(reinterpret_cast<char*>(family)) == folded(name);
  }
  if (!exact) throw std::runtime_error("Font is unavailable");
  double actual_weight = FC_WEIGHT_REGULAR;
  int actual_slant = FC_SLANT_ROMAN;
  FcPatternGetDouble(pattern, FC_WEIGHT, 0, &actual_weight);
  FcPatternGetInteger(pattern, FC_SLANT, 0, &actual_slant);
  Face face{{}, std::clamp(static_cast<int>(std::lround(FcWeightToOpenTypeDouble(actual_weight))), 1, 1000), actual_slant != FC_SLANT_ROMAN};
  for (const char* field : {FC_POSTSCRIPT_NAME, FC_FULLNAME}) {
    auto source = pattern_string(pattern, field);
    if (ValidName(source) && std::find(face.sources.begin(), face.sources.end(), source) == face.sources.end()) face.sources.push_back(source);
  }
  // Chromium resolves full/PostScript face identities. WebKitGTK's FreeType
  // port also needs a family alternative, matched with actual weight/style.
  const auto family = pattern_string(pattern, FC_FAMILY);
  if (ValidName(family) && std::find(face.sources.begin(), face.sources.end(), family) == face.sources.end()) face.sources.push_back(family);
  if (face.sources.empty()) throw std::runtime_error("Local font has no usable face identity");
  return {std::move(font), pattern_string(pattern, FC_FAMILY), std::move(face)};
}
void color(cairo_t* cr, uint32_t value) { cairo_set_source_rgb(cr, ((value >> 16) & 255) / 255., ((value >> 8) & 255) / 255., (value & 255) / 255.); }
}
bool ValidName(const std::string& value) {
  if (value.empty() || !g_utf8_validate(value.c_str(), value.size(), nullptr) || g_utf8_strlen(value.c_str(), value.size()) > 256) return false;
  if (g_unichar_isspace(g_utf8_get_char(value.c_str())) || g_unichar_isspace(g_utf8_get_char(g_utf8_find_prev_char(value.c_str(), value.c_str() + value.size())))) return false;
  size_t units = 0;
  for (const char* p = value.c_str(); p < value.c_str() + value.size(); p = g_utf8_next_char(p)) {
    auto ch = g_utf8_get_char(p);
    if (ch < 32 || (ch >= 127 && ch <= 159) || ch == 0xfffd) return false;
    units += ch > 0xffff ? 2 : 1;
    if (units > 256) return false;
  }
  return true;
}
std::vector<Family> Discover(bool refresh) { std::lock_guard<std::mutex> lock(mutex); discover(refresh); return catalogue; }
Resolution Resolve(const std::string& requested, bool generic) {
  std::lock_guard<std::mutex> lock(mutex);
  const auto name = identity(requested, generic);
  auto map = font_map(); Owned<PangoContext> context(pango_font_map_create_context(map.get()));
  if (!generic) literal_family(map.get(), name);
  Resolution result{match(map.get(), context.get(), name, generic, 400, false).family, {}};
  if (generic) literal_family(map.get(), result.family);
  // Include the existing body weights and CSS relative-bold weights. Preserve
  // actual matches (including intermediate OpenType weights), never relabel a
  // nearest face as the requested one. Registration coalesces repeated matches.
  for (int weight = 100; weight <= 900; weight += 100) {
    for (bool italic : {false, true}) result.faces.push_back(match(map.get(), context.get(), result.family, false, weight, italic).face);
  }
  return result;
}
std::vector<uint8_t> Preview(const std::string& requested, bool generic, const Sample& sample) {
  std::lock_guard<std::mutex> lock(mutex);
  const auto name = identity(requested, generic);
  auto map = font_map(); Owned<PangoContext> context(pango_font_map_create_context(map.get()));
  if (!generic) literal_family(map.get(), name);
  const auto resolved = match(map.get(), context.get(), name, generic, 400, false).family;
  if (generic) literal_family(map.get(), resolved);
  const int width = std::clamp(sample.width, 80, 800), height = std::clamp(sample.height, 60, 240);
  const double scale = std::clamp(sample.scale, 1., 3.);
  std::unique_ptr<cairo_surface_t, decltype(&cairo_surface_destroy)> surface(cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width * scale, height * scale), cairo_surface_destroy);
  std::unique_ptr<cairo_t, decltype(&cairo_destroy)> cr(cairo_create(surface.get()), cairo_destroy);
  cairo_scale(cr.get(), scale, scale); color(cr.get(), sample.background); cairo_paint(cr.get()); color(cr.get(), sample.foreground);
  double y = 8;
  const std::string lines[] = {sample.prose, sample.bold, sample.italic};
  const int base_weight = std::clamp(sample.weight, 300, 700), bold_weight = base_weight < 350 ? 400 : base_weight < 550 ? 700 : 900;
  for (int i = 0; i < 3; ++i) {
    const int weight = i == 1 ? bold_weight : base_weight;
    auto face = match(map.get(), context.get(), resolved, false, weight, i == 2);
    Owned<PangoLayout> layout(pango_layout_new(context.get()));
    auto* desc = pango_font_describe(face.font.get());
    pango_font_description_set_family(desc, literal_alias);
    pango_font_description_set_weight(desc, static_cast<PangoWeight>(weight));
    pango_font_description_set_style(desc, i == 2 ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL);
    pango_font_description_set_absolute_size(desc, std::clamp(sample.size, 14., 28.) * PANGO_SCALE);
    pango_layout_set_font_description(layout.get(), desc); pango_font_description_free(desc);
    pango_layout_set_width(layout.get(), (width - 16) * PANGO_SCALE);
    pango_layout_set_height(layout.get(), -1); pango_layout_set_ellipsize(layout.get(), PANGO_ELLIPSIZE_END);
    pango_layout_set_text(layout.get(), lines[i].c_str(), lines[i].size());
    cairo_move_to(cr.get(), 8, y); pango_cairo_show_layout(cr.get(), layout.get());
    int h = 0; pango_layout_get_pixel_size(layout.get(), nullptr, &h);
    y += std::min(std::max(h * std::clamp(sample.line, 1., 1.6), 28.), (height - 16) / 3.);
  }
  std::vector<uint8_t> bytes;
  auto status = cairo_surface_write_to_png_stream(surface.get(), +[](void* data, const unsigned char* chunk, unsigned length) {
    auto& out = *static_cast<std::vector<uint8_t>*>(data); out.insert(out.end(), chunk, chunk + length); return CAIRO_STATUS_SUCCESS;
  }, &bytes);
  if (status != CAIRO_STATUS_SUCCESS) throw std::runtime_error("Font preview could not be rendered");
  return bytes;
}
}
