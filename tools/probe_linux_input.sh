#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/busybooks-input-probe-XXXXXX)
menu_test=$(mktemp /tmp/busybooks-menu-contract-XXXXXX)
popover_test=$(mktemp /tmp/busybooks-popover-geometry-XXXXXX)
trap 'rm -f "$binary" "$menu_test" "$popover_test"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror test/src/native_menu_selection_test.cc -o "$menu_test"
"$menu_test"
g++ -std=c++17 -Wall -Wextra -Werror test/src/native_popover_geometry_test.cc -o "$popover_test"
"$popover_test"
g++ -std=c++17 -Wall -Wextra -Werror -Ilinux/runner \
  test/src/linux_reader_surface_test.cc linux/runner/reader_surface.cc \
  linux/runner/gtk_window_menu.cc \
  -o "$binary" $(pkg-config --cflags --libs gtk+-3.0 x11) -ldl
"$binary"
