#ifndef BUSYBOOKS_READING_FONTS_H_
#define BUSYBOOKS_READING_FONTS_H_
#include <cstdint>
#include <string>
#include <vector>

// Application-owned local fonts only. No paths or publication-provided sources
// cross this boundary. Implementations own native resources on the calling
// worker, and serialize their process-wide catalogue (shared by Flutter engines).
namespace reading_fonts {
struct Family { std::string id, label; };
struct Face { std::vector<std::string> sources; int weight; bool italic; };
struct Resolution { std::string family; std::vector<Face> faces; };
struct Sample {
  std::string prose, bold, italic;
  int width = 360, height = 150;
  int weight = 400;
  double scale = 1, size = 20, line = 1.5;
  uint32_t foreground = 0xff242424, background = 0xffffffff;
};
bool ValidName(const std::string& value);
std::vector<Family> Discover(bool refresh);
Resolution Resolve(const std::string& name, bool generic);
std::vector<uint8_t> Preview(const std::string& name, bool generic, const Sample& sample);
}
#endif
