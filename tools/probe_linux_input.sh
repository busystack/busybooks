#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/busybooks-input-probe-XXXXXX)
trap 'rm -f "$binary"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror -Ilinux/runner \
  test/src/linux_reader_surface_test.cc linux/runner/reader_surface.cc \
  -o "$binary" $(pkg-config --cflags --libs gtk+-3.0 x11) -ldl
"$binary"
