#!/usr/bin/env python3
"""Rasterize the canonical SVG into a header PNG and multi-resolution ICO.

Requires system gdk-pixbuf/librsvg loaders and C++ build tools on Linux.
Does not modify an installed application or shared dependency cache.
"""
import pathlib
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SIZES = (16, 24, 32, 48, 64, 128, 256)
with tempfile.TemporaryDirectory(prefix='busybooks-icons-') as directory:
    temp = pathlib.Path(directory)
    source = temp / 'rasterize.cc'
    source.write_text('''#include <gdk-pixbuf/gdk-pixbuf.h>
#include <cstdlib>
int main(int argc,char** argv){GError* error=nullptr;
auto* image=gdk_pixbuf_new_from_file_at_scale(argv[1],atoi(argv[3]),atoi(argv[3]),TRUE,&error);
if(!image){g_printerr("%s",error->message);return 1;}
bool ok=gdk_pixbuf_save(image,argv[2],"png",&error,nullptr);g_object_unref(image);
if(!ok){g_printerr("%s",error->message);return 1;}return 0;}
''')
    flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'gdk-pixbuf-2.0'], text=True).split()
    subprocess.run(['g++', str(source), '-o', str(temp / 'rasterize'), *flags], check=True)
    images = []
    for size in SIZES:
        png = temp / f'{size}.png'
        subprocess.run([str(temp / 'rasterize'), str(ROOT / 'assets/branding/busybooks_logo.svg'), str(png), str(size)], check=True)
        images.append(png.read_bytes())
    # flutter_svg does not support the approved artwork's SVG shadow filter.
    # Keep the SVG unchanged and let librsvg render this faithful derivative.
    subprocess.run([str(temp / 'rasterize'), str(ROOT / 'assets/branding/busybooks_logo.svg'),
                    str(ROOT / 'assets/branding/busybooks_logo.png'), '512'], check=True)
    offset = 6 + 16 * len(SIZES)
    output = struct.pack('<HHH', 0, 1, len(SIZES))
    for size, image in zip(SIZES, images):
        output += struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(image), offset)
        offset += len(image)
    (ROOT / 'windows/runner/resources/app_icon.ico').write_bytes(output + b''.join(images))
