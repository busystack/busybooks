#ifndef BUSYBOOKS_COMIC_RESOURCE_POLICY_H_
#define BUSYBOOKS_COMIC_RESOURCE_POLICY_H_

#include <cstdint>
#include <set>
#include <string>

namespace busybooks {
constexpr uint64_t kMiB = 1024 * 1024;
enum class ComicResource { page, info, discard };

inline ComicResource comic_resource(const std::string& name) {
  for (std::size_t at = 0; at < name.size();) {
    const auto end = name.find('/', at);
    const auto component = name.substr(
        at, end == name.npos ? name.size() - at : end - at);
    if (component == "__MACOSX" || component == ".DS_Store" ||
        component.rfind("._", 0) == 0) {
      return ComicResource::discard;
    }
    if (end == name.npos) break;
    at = end + 1;
  }
  const auto slash = name.find_last_of('/');
  auto base = name.substr(slash == name.npos ? 0 : slash + 1);
  for (char& c : base) {
    if (c >= 'A' && c <= 'Z') c += 32;
  }
  const auto dot = base.find_last_of('.');
  const auto extension = dot == base.npos ? "" : base.substr(dot);
  static const std::set<std::string> pages = {
      ".jpg", ".jpeg", ".jpe", ".jfif", ".png", ".webp"};
  static const std::set<std::string> unsupported = {
      ".gif", ".bmp", ".tif", ".tiff", ".avif", ".heic", ".heif",
      ".jxl", ".jp2", ".j2k", ".jpf", ".svg", ".ico", ".ppm",
      ".pnm", ".pgm", ".pbm", ".dib", ".jng", ".apng", ".jxr",
      ".wdp", ".hdp", ".dds", ".tga", ".psd"};
  if (pages.count(extension)) return ComicResource::page;
  if (unsupported.count(extension)) {
    throw std::string("Unsupported comic page image: ") + name;
  }
  return base == "comicinfo.xml" ? ComicResource::info : ComicResource::discard;
}

struct ComicResourceBudget {
  uint64_t retained = 0, discarded = 0;
  unsigned metadata = 0, pages = 0;

  ComicResource add(const std::string& name, uint64_t size) {
    const auto kind = comic_resource(name);
    if (kind == ComicResource::page && ++pages > 10000) {
      throw std::string("A comic must contain 1 to 10000 supported pages");
    }
    if (size > 64 * kMiB) {
      throw std::string("Comic entry resource limit exceeded (64 MiB)");
    }
    if (kind == ComicResource::discard) {
      discarded += size;
      if (discarded > 128 * kMiB) {
        throw std::string(
            "Discarded comic resources exceed the 128 MiB verification budget");
      }
    } else {
      if (kind == ComicResource::info &&
          (size > kMiB || ++metadata > 1)) {
        throw std::string("ComicInfo.xml must be unique and at most 1 MiB");
      }
      retained += size;
      if (retained > 4096 * kMiB) {
        throw std::string("Comic page resource limit exceeded");
      }
    }
    return kind;
  }
};
}  // namespace busybooks
#endif  // BUSYBOOKS_COMIC_RESOURCE_POLICY_H_
