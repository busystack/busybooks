// BusyBooks' bounded RAR-only worker. No shell, network, external extractor,
// archive-controlled output paths or persistent reading data are involved.
// The bundled UnRAR source is unmodified. Its required license paragraph:
// UnRAR source code may be used in any software to handle
// RAR archives without limitations free of charge, but cannot be
// used to develop RAR (WinRAR) compatible archiver and to
// re-create RAR compression algorithm, which is proprietary.
// Distribution of modified UnRAR source code in separate form
// or as a part of other software is permitted, provided that
// full text of this paragraph, starting from "UnRAR source code"
// words, is included in license, or in documentation if license
// is not available, and in source code comments of resulting package.
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <string>
#include <vector>
#include <codecvt>
#include <locale>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/resource.h>
#endif
#include "dll.hpp"

static constexpr uint64_t MiB = 1024 * 1024;
static std::string json(const std::string& s) {
  std::string out = "\"";
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') { out += '\\'; out += c; }
    else if (c < 32) {
      char escaped[7]; std::snprintf(escaped, sizeof escaped, "\\u%04x", c); out += escaped;
    } else out += c;
  }
  return out + '"';
}
static uint64_t vint(std::ifstream& file) {
  uint64_t n = 0;
  for (unsigned i = 0; i < 10; ++i) {
    int c = file.get();
    if (c < 0 || (i == 9 && (c & 0xfe))) throw std::string("Damaged RAR header");
    n |= uint64_t(c & 127) << (i * 7);
    if (!(c & 128)) return n;
  }
  throw std::string("Damaged RAR integer");
}
static void profile(const std::filesystem::path& source) {
  std::ifstream f(source, std::ios::binary);
  unsigned char marker[8] = {}; f.read(reinterpret_cast<char*>(marker), 8);
  if (std::memcmp(marker, "Rar!\x1a\x07", 6)) throw std::string("Invalid RAR signature");
  if (marker[6] == 0) {
    f.seekg(7); unsigned char h[7] = {}; f.read(reinterpret_cast<char*>(h), 7);
    if (!f || h[2] != 0x73) throw std::string("Damaged RAR4 main header");
    const unsigned flags = h[3] | (h[4] << 8);
    if (flags & 1) throw std::string("Multipart RAR archives are unsupported; use one complete archive");
    if (flags & 0x80) throw std::string("Encrypted RAR headers are unsupported");
    // Unlabelled, non-ASCII RAR4 names depend on an operating system OEM
    // codepage. Require ASCII or RAR's Unicode filename field so page identity
    // and ordering cannot change between Windows and Linux or by locale.
    uint64_t at = 7; unsigned headers = 0;
    const uint64_t source_size = std::filesystem::file_size(source);
    while (at + 7 <= source_size) {
      f.seekg(static_cast<std::streamoff>(at));
      unsigned char base[7]{}; f.read(reinterpret_cast<char*>(base), 7);
      const unsigned block_flags = base[3] | (unsigned(base[4]) << 8);
      const unsigned size = base[5] | (unsigned(base[6]) << 8);
      if (!f || size < 7 || at + size > source_size || ++headers > 40000) throw std::string("Damaged RAR4 header or header resource limit exceeded");
      std::vector<unsigned char> block(size); std::memcpy(block.data(), base, 7);
      f.read(reinterpret_cast<char*>(block.data() + 7), size - 7);
      const auto u32 = [&](unsigned offset) -> uint64_t {
        if (offset + 4 > size) throw std::string("Damaged RAR4 size field");
        return uint64_t(block[offset]) | (uint64_t(block[offset+1]) << 8) | (uint64_t(block[offset+2]) << 16) | (uint64_t(block[offset+3]) << 24);
      };
      uint64_t packed = block_flags & 0x8000 ? u32(7) : 0;
      if (base[2] == 0x74) {
        if (size < 32) throw std::string("Damaged RAR4 file header");
        const unsigned name_size = block[26] | (unsigned(block[27]) << 8);
        const unsigned name_at = block_flags & 0x100 ? 40 : 32;
        if (block_flags & 0x100) packed |= u32(32) << 32;
        if (name_at + name_size > size) throw std::string("Damaged RAR4 filename");
        bool high = false, zero = false;
        for (unsigned i = name_at; i < name_at + name_size; ++i) {
          if (block[i] == 0) { zero = i + 1 < name_at + name_size; break; }
          if (block[i] > 127) high = true;
        }
        if ((!(block_flags & 0x200) && (high || zero)) || ((block_flags & 0x200) && high && !zero)) throw std::string("Unsupported RAR4 filename encoding; use Unicode filenames");
      }
      if (packed > source_size - at - size) throw std::string("Damaged RAR4 packed size");
      at += size + packed;
      if (base[2] == 0x7b) break;
    }
  } else if (marker[6] == 1 && marker[7] == 0) {
    f.seekg(12); const auto size = vint(f); const auto start = f.tellg();
    if (size > MiB) throw std::string("RAR header resource limit exceeded");
    const auto type = vint(f), flags = vint(f);
    if (type == 4) throw std::string("Encrypted RAR headers are unsupported");
    if (type != 1) throw std::string("Damaged RAR5 main header");
    if (flags & 1) vint(f);
    if (flags & 2) vint(f);
    if (vint(f) & 3) throw std::string("Multipart RAR archives are unsupported; use one complete archive");
    if (!f || f.tellg() - start > static_cast<std::streamoff>(size)) throw std::string("Damaged RAR5 header");
  } else throw std::string("Unsupported RAR generation");
}
struct OutputState {
  std::ofstream output;
  uint64_t size = 0, total = 0, declared = 0;
  std::string error;
};
static int CALLBACK data_callback(UINT message, LPARAM user, LPARAM p1, LPARAM p2) {
  auto* state = reinterpret_cast<OutputState*>(user);
  if (message != UCM_PROCESSDATA) {
    state->error = message == UCM_LARGEDICT ? "RAR dictionary resource limit exceeded" : "Encrypted or multipart RAR archives are unsupported";
    return -1;
  }
  if (p2 < 0 || static_cast<uint64_t>(p2) > 64 * MiB) return -1;
  state->size += static_cast<uint64_t>(p2); state->total += static_cast<uint64_t>(p2);
  if (state->size > state->declared || state->size > 64 * MiB || state->total > 4096 * MiB) {
    state->error = "RAR decompressed resource limit exceeded"; return -1;
  }
  if (state->output.is_open()) {
    state->output.write(reinterpret_cast<const char*>(p1), static_cast<std::streamsize>(p2));
    if (!state->output) { state->error = "Cannot write comic cache"; return -1; }
  }
  return 1;
}
static int run(const std::filesystem::path& source, const std::filesystem::path& destination) {
  HANDLE archive = nullptr;
  try {
    if (!std::filesystem::is_regular_file(source) || std::filesystem::file_size(source) > 1024 * MiB)
      throw std::string("Comic source resource limit exceeded (1 GiB)");
    profile(source);
    OutputState state;
    RAROpenArchiveDataEx options{};
    options.OpenMode = RAR_OM_EXTRACT; options.Callback = data_callback;
    options.UserData = reinterpret_cast<LPARAM>(&state);
#ifdef _WIN32
    std::wstring source_name = source.wstring(); options.ArcNameW = source_name.data();
#else
    std::string source_name = source.string(); options.ArcName = source_name.data();
#endif
    archive = RAROpenArchiveEx(&options);
    if (!archive || options.OpenResult) throw std::string("Cannot open RAR archive (decoder error ") + std::to_string(options.OpenResult) + ")";
    if (options.Flags & ROADF_VOLUME) throw std::string("Multipart RAR archives are unsupported");
    if (options.Flags & ROADF_ENCHEADERS) throw std::string("Encrypted RAR headers are unsupported");
    std::set<std::string> names; unsigned count = 0;
    while (true) {
      RARHeaderDataEx header{};
      std::vector<wchar_t> full_name(32768);
      header.FileNameEx = full_name.data(); header.FileNameExSize = static_cast<unsigned>(full_name.size());
      const int status = RARReadHeaderEx(archive, &header);
      if (status == ERAR_END_ARCHIVE) break;
      if (status != ERAR_SUCCESS) throw std::string("Damaged or unsupported RAR header (decoder error ") + std::to_string(status) + ")";
#ifdef _WIN32
      std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> encoding;
#else
      std::wstring_convert<std::codecvt_utf8<wchar_t>> encoding;
#endif
      std::string name = encoding.to_bytes(full_name.data());
      // RAR uses DOS separators even on Unix; canonical logical paths use '/'.
      for (char& c : name) if (c == '\\') c = '/';
      if (++count > 20000 || name.empty() || name.size() > 32768 || std::wcslen(full_name.data()) >= full_name.size()-1 || name[0] == '/' ||
          name.find(':') != name.npos || !names.insert(name).second || header.RedirType ||
          (header.HostOS == 3 && (header.FileAttr & 0170000) != 0 &&
           (header.FileAttr & 0170000) != 0100000 && (header.FileAttr & 0170000) != 0040000))
        throw std::string("Unsafe, linked or duplicate RAR path");
      std::string component;
      for (size_t i = 0; i <= name.size(); ++i) {
        if (i == name.size() || name[i] == '/') {
          if (component == ".." || component == "." || (component.empty() && i != name.size())) throw std::string("Unsafe RAR path");
          component.clear();
        } else component += name[i];
      }
      if (header.Flags & (RHDF_SPLITBEFORE | RHDF_SPLITAFTER)) throw std::string("Multipart RAR entries are unsupported");
      if (header.Flags & RHDF_ENCRYPTED) throw std::string("Encrypted RAR entries are unsupported");
      if (header.DictSize > 256 * 1024) throw std::string("RAR dictionary resource limit exceeded (256 MiB)");
      state.declared = uint64_t(header.UnpSize) | (uint64_t(header.UnpSizeHigh) << 32); state.size = 0;
      if (state.declared > 64 * MiB) throw std::string("RAR entry resource limit exceeded (64 MiB)");
      const bool directory = (header.Flags & RHDF_DIRECTORY) != 0;
      const auto filename = std::to_string(count);
      if (!directory) {
        state.output.open(destination / filename, std::ios::binary | std::ios::trunc);
        if (!state.output) throw std::string("Cannot open comic staging resource");
      }
      // RAR_TEST performs CRC/hash validation and sends bytes to our bounded
      // callback. It never creates archive-named files, links or volumes.
      const int decoded = RARProcessFileW(archive, RAR_TEST, nullptr, nullptr);
      if (state.output.is_open()) state.output.close();
      if (decoded != ERAR_SUCCESS) throw state.error.empty() ? std::string("Damaged or unsupported RAR data (decoder error ") + std::to_string(decoded) + ")" : state.error;
      if (state.size != state.declared) throw std::string("Damaged RAR entry size");
      if (!directory) std::cout << "{\"name\":" << json(name) << ",\"file\":" << json(filename) << ",\"size\":" << state.size << "}\n";
    }
    RARCloseArchive(archive); return 0;
  } catch (const std::string& error) {
    if (archive) RARCloseArchive(archive);
    std::cerr << error.substr(0, 4096) << '\n'; return 2;
  } catch (const std::exception& error) {
    if (archive) RARCloseArchive(archive);
    std::cerr << "Comic decoding failed: " << error.what() << '\n'; return 2;
  }
}
#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limit{};
  limit.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_PROCESS_MEMORY;
  limit.ProcessMemoryLimit = 768 * MiB;
  if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limit, sizeof limit) ||
      !AssignProcessToJobObject(job, GetCurrentProcess())) return 3;
#else
int main(int argc, char** argv) {
  struct rlimit memory = {768 * MiB, 768 * MiB};
  if (setrlimit(RLIMIT_AS, &memory)) return 3;
#endif
  if (argc != 3) return 2;
  return run(std::filesystem::path(argv[1]), std::filesystem::path(argv[2]));
}
