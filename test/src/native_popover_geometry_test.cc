#include <cassert>
#include <cmath>
#include <limits>
#include "../../native/reader_popover_geometry.h"

static void Within(const ReaderPopoverPlacement& result, ReaderPopoverRect pane) {
  assert(result.body.width > 0 && result.body.height > 0);
  assert(result.body.x >= pane.x && result.body.y >= pane.y);
  assert(result.body.x + result.body.width <= pane.x + pane.width);
  assert(result.body.y + result.body.height <= pane.y + pane.height);
}

int main() {
  const ReaderPopoverRect pane{300, 48, 400, 650};
  // Header controls can originate above and to the right of the reader pane.
  const auto header = PlaceReaderPopover(pane, {1020, 20, 24, 24}, 460, 650, 12, true);
  Within(header, pane);
  assert(header.body.width == 376 && header.body.height == 626);
  assert(header.body.x == 312 && header.body.y == 60);
  const auto selection = PlaceReaderPopover(pane, {650, 660, 40, 18}, 460, 340, 12, true);
  Within(selection, pane);
  assert(selection.above);
  assert(selection.body.y + selection.body.height < 660);
  // The same pane coordinates converted once to physical pixels retain layout.
  const auto scaled = PlaceReaderPopover(
      {600, 96, 800, 1300}, {1300, 1320, 80, 36}, 920, 680, 24, true);
  assert(scaled.body.x == 2 * selection.body.x);
  assert(scaled.body.y == 2 * selection.body.y);
  assert(scaled.body.width == 2 * selection.body.width);
  assert(scaled.body.height == 2 * selection.body.height);
  // A shorter measured body is placed again within the same owned pane.
  Within(PlaceReaderPopover(pane, {650, 660, 40, 18}, 376, 180), pane);
  Within(PlaceReaderPopover({312.5, 48.5, 487.5, 641.25},
      {810.75, 23.5, 1, 1}, 460, 480, 12, true), {312.5, 48.5, 487.5, 641.25});
  assert(!ValidReaderPopoverRect({0, 0, 0, 650}));
  assert(!ValidReaderPopoverRect({0, 0, std::numeric_limits<double>::infinity(), 650}));
  Within(PlaceReaderPopover({0, 0, .5, .5}, {0, 0, 1, 1}, 460, 480), {0, 0, .5, .5});
}
