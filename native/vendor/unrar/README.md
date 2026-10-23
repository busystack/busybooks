# Pinned RAR decoder source

Official RARLAB UnRAR 7.21 stable (the source archive retains the filename
`unrarsrc-7.2.6.tar.gz`):

Source: https://www.rarlab.com/rar/unrarsrc-7.2.6.tar.gz

SHA-256: `d1afa67ef4121ebc5986815699e05db0ce8648499e5dca854f282a4c3f72c003`

The archive is unmodified. CMake verifies this checksum and builds only the
official makefile's RARDLL/UNRAR object set into BusyBooks' separate RAR-only
worker. It does not build or distribute a compressor, command-line UnRAR program,
or runtime-downloaded library. No optional third-party library is required.

`license.txt` and `acknow.txt` are copied from that source distribution with LF
line endings. The complete terms/acknowledgements also install alongside the
helper. They permit free RAR handling and redistribution, including inclusion in
other software, but prohibit developing a RAR-compatible archiver or recreating
the proprietary compression algorithm. This dependency has its own license;
BusyBooks' application code remains Apache-2.0. The wrapper retains the required
license paragraph in source comments as well.

Qualification and unsupported profiles are documented in
`docs/development/format-verification.md`. In particular, libarchive 3.8.10 was
tested first and rejected because a representative RAR4 solid fixture failed;
the selected UnRAR backend decodes all six qualified profiles.
