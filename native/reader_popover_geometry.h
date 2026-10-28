#ifndef BUSYBOOKS_READER_POPOVER_GEOMETRY_H_
#define BUSYBOOKS_READER_POPOVER_GEOMETRY_H_

#include <algorithm>
#include <cmath>

struct ReaderPopoverRect {
  double x, y, width, height;
};

inline bool ValidReaderPopoverRect(const ReaderPopoverRect& rect) {
  return std::isfinite(rect.x) && std::isfinite(rect.y) &&
      std::isfinite(rect.width) && std::isfinite(rect.height) &&
      std::isfinite(rect.x + rect.width) && std::isfinite(rect.y + rect.height) &&
      rect.width > 0 && rect.height > 0;
}

struct ReaderPopoverPlacement {
  ReaderPopoverRect body;
  double pointing_x, pointing_y;
  bool above;
};

// All inputs share one coordinate space. The inset reserves native borders,
// shadows and the GTK arrow without reducing text scale or clipping controls.
inline ReaderPopoverPlacement PlaceReaderPopover(
    ReaderPopoverRect pane, ReaderPopoverRect anchor,
    double requested_width, double requested_height,
    double inset = 12, bool centered = false) {
  if (!ValidReaderPopoverRect(pane) || !ValidReaderPopoverRect(anchor) ||
      !std::isfinite(requested_width) || !std::isfinite(requested_height)) {
    return {{0, 0, 0, 0}, 0, 0, false};
  }
  inset = std::clamp(inset, 0.0,
      std::max(0.0, (std::min(pane.width, pane.height) - 1) / 2));
  const double width = std::clamp(requested_width,
      std::min(1.0, pane.width - 2 * inset), pane.width - 2 * inset);
  const double height = std::clamp(requested_height,
      std::min(1.0, pane.height - 2 * inset), pane.height - 2 * inset);
  const double left = pane.x + inset, top = pane.y + inset;
  const double right = pane.x + pane.width - inset;
  const double bottom = pane.y + pane.height - inset;
  const double desired_x = centered ? anchor.x + (anchor.width - width) / 2 : anchor.x;
  const double below = anchor.y + anchor.height + inset;
  const double above_y = anchor.y - inset - height;
  const bool above = below + height > bottom && above_y >= top;
  const double x = std::clamp(desired_x, left, right - width);
  const double y = std::clamp(above ? above_y : below, top, bottom - height);
  return {{x, y, width, height}, x + width / 2,
      above ? y + height + inset : y - inset, above};
}

#endif
