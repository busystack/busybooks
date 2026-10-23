#ifndef BUSYBOOKS_READER_ACTION_LIMITS_H_
#define BUSYBOOKS_READER_ACTION_LIMITS_H_
#include <cstddef>
// The existing note contract: 1,000,000 UTF-16 units, worst-case JSON escaping
// (six UTF-8 bytes per unit), plus a bounded 64 KiB action envelope. Exclusive
// to the Flutter popover, with no change to publication renderer permissions.
// Keep lib/src/reading/domain/reader_action.dart in agreement (tested).
constexpr std::size_t kMaxReaderPopoverActionBytes = 6 * 1000000 + 65536;
#endif
