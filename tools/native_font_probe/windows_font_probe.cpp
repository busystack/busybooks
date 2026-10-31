// Native Windows acceptance probe, using stock Windows desktop families.
// This does not establish WebView2 rendering or popover accessibility.
#include "../../native/reading_fonts.h"
#include <algorithm>
#include <cstdio>
#include <stdexcept>

int main() {
  try {
    const auto families = reading_fonts::Discover(true);
    if (families.empty()) throw std::runtime_error("No local Windows fonts");
    for (const std::string name : {"Arial", "Times New Roman"}) {
      if (std::none_of(families.begin(), families.end(), [&](const auto& f) { return f.id == name; })) throw std::runtime_error("Stock Windows desktop family missing: " + name);
      const auto resolved = reading_fonts::Resolve(name, false);
      if (resolved.family != name || resolved.faces.empty() || resolved.faces.size() > 18) throw std::runtime_error("Native family resolution mismatch");
      for (const auto& face : resolved.faces) if (face.sources.empty()) throw std::runtime_error("Missing local face identity");
    }
    reading_fonts::Sample sample; sample.prose = "An open book, 0123456789."; sample.bold = "Bold emphasis."; sample.italic = "An italic voice.";
    const auto sans = reading_fonts::Preview("Arial", false, sample), serif = reading_fonts::Preview("Times New Roman", false, sample);
    if (sans.size() < 100 || serif.size() < 100 || sans == serif) throw std::runtime_error("Distinct native family previews did not render");
    bool rejected = false;
    try { reading_fonts::Resolve("BusyBooks deliberately missing font", false); }
    catch (const std::exception&) { rejected = true; }
    if (!rejected) throw std::runtime_error("Missing family was not rejected");
    if (!reading_fonts::ValidName("A \"quote\", \\ family") || reading_fonts::ValidName("Bad\nName")) throw std::runtime_error("Invalid family validation");
    printf("WINDOWS_FONT_PROBE passed families=%zu distinct_previews=1 cloud_downloads=0\n", families.size());
    return 0;
  } catch (const std::exception& error) { fprintf(stderr, "%s\n", error.what()); return 1; }
}
