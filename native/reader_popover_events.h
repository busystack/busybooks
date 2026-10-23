#ifndef BUSYBOOKS_READER_POPOVER_EVENTS_H_
#define BUSYBOOKS_READER_POPOVER_EVENTS_H_
#include <cstdint>
#include <string>

// Native dismissal must invalidate requests even when there is no action from
// the transient Flutter view (outside click, deactivation, or geometry change).
inline std::string ReaderPopoverHiddenEvent(const std::string& session, int64_t presentation, bool keyboard = false) {
  std::string escaped;
  constexpr char hex[] = "0123456789abcdef";
  for (unsigned char c : session) {
    if (c == '"' || c == '\\') { escaped += '\\'; escaped += c; }
    else if (c < 32) { escaped += "\\u00"; escaped += hex[c >> 4]; escaped += hex[c & 15]; }
    else escaped += c;
  }
  return "{\"type\":\"popoverHidden\",\"session\":\"" + escaped +
      "\",\"presentation\":" + std::to_string(presentation) +
      (keyboard ? ",\"keyboard\":true}" : "}");
}
#endif
