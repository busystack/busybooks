"""Validate native formats without depending on a host-specific compilation."""
import io
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from verify_distribution import verify_native


def elf(machine=62, bits=2):
    header = bytearray(64)
    header[:6] = b'\x7fELF' + bytes([bits, 1])
    struct.pack_into('<H', header, 18, machine)
    return bytes(header)


def pe(machine=0x8664):
    header = bytearray(70)
    header[:2] = b'MZ'
    struct.pack_into('<I', header, 60, 64)
    header[64:68] = b'PE\0\0'
    struct.pack_into('<H', header, 68, machine)
    return bytes(header)


class DistributionNativeTest(unittest.TestCase):
    def test_windows_flutter_aot_is_x64_elf(self):
        verify_native(io.BytesIO(elf()), Path('data/app.so'), 'windows')
        for invalid in [pe(), elf(machine=183), elf(bits=1), b'\x7fELF']:
            with self.subTest(header=invalid), self.assertRaises(ValueError):
                verify_native(io.BytesIO(invalid), Path('data/app.so'), 'windows')

    def test_windows_app_and_libraries_require_x64_pe(self):
        for name in ['busybooks.exe', 'flutter_windows.dll', 'other.so']:
            with self.subTest(name=name):
                verify_native(io.BytesIO(pe()), Path(name), 'windows')
                for invalid in [pe(machine=0x14c), elf(), b'MZ']:
                    with self.assertRaises(ValueError):
                        verify_native(io.BytesIO(invalid), Path(name), 'windows')

    def test_only_named_runtime_and_uninstaller_bootstraps_allow_x86(self):
        for name in ['VC_redist.x64.exe', 'MicrosoftEdgeWebView2RuntimeInstallerX64.exe', 'unins000.exe']:
            with self.subTest(name=name):
                verify_native(io.BytesIO(pe(machine=0x14c)), Path(name), 'windows')
                with self.assertRaises(ValueError):
                    verify_native(io.BytesIO(pe(machine=0x14c)), Path('nested') / name, 'windows')

    def test_linux_native_files_require_x64_elf(self):
        for name in ['busybooks', 'lib/libapp.so', 'lib/libsqlite3.so.0']:
            with self.subTest(name=name):
                verify_native(io.BytesIO(elf()), Path(name), 'linux')
                for invalid in [pe(), elf(machine=183), elf(bits=1)]:
                    with self.assertRaises(ValueError):
                        verify_native(io.BytesIO(invalid), Path(name), 'linux')


if __name__ == '__main__':
    unittest.main()
