"""Application-owned synthetic dependency fixtures; no third-party edits."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('verify_vendor', Path(__file__).resolve().parents[2] / 'tools/verify_vendor.py')
vendor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vendor)


class VendorIntegrityTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='busybooks-vendor-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repository = self.root / 'repository'
        self.bundle = self.root / 'bundle'
        self.name = 'assets/reader/vendor/synthetic/reader.js'
        self.payload = b'// Application-owned synthetic implementation.\n'
        self.archive = self.root / 'synthetic.zip'
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr('upstream/reader.js', self.payload)
        self.manifest = {
            'schemaVersion': 2,
            'vendorRoots': ['assets/reader/vendor'],
            'sources': {'synthetic': {'kind': 'zip', 'url': 'https://example.invalid/official-v1.zip', 'release': '1', 'sha256': vendor.digest(self.archive.read_bytes())}},
            'sha256': {self.name: vendor.digest(self.payload)},
            'provenance': {self.name: {'source': 'synthetic', 'path': 'upstream/reader.js'}},
            'bundleNotices': [],
        }
        self.write(self.repository, self.name, self.payload)
        self.bundle_name = 'data/flutter_assets/' + self.name
        self.write(self.bundle, self.bundle_name, self.payload)
        (self.bundle / 'share/licenses/unrar').mkdir(parents=True)

    def write(self, root, name, payload):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return path

    def load(self, manifest=None):
        path = self.root / 'manifest.json'
        path.write_text(json.dumps(manifest or self.manifest))
        return vendor.load_manifest(path)

    def test_official_baseline_and_bundle_match(self):
        manifest = self.load()
        vendor.verify_repository(manifest, self.repository)
        vendor.verify_upstream(manifest, {'synthetic': self.archive})
        vendor.verify_bundle(manifest, self.bundle, 'linux')

    def test_modified_missing_and_unexpected_repository_files(self):
        path = self.repository / self.name
        path.write_bytes(b'changed')
        with self.assertRaisesRegex(vendor.VerificationError, 'checksum mismatch'):
            vendor.verify_repository(self.load(), self.repository)
        path.unlink()
        with self.assertRaisesRegex(vendor.VerificationError, 'missing='):
            vendor.verify_repository(self.load(), self.repository)
        path.write_bytes(self.payload)
        self.write(self.repository, 'assets/reader/vendor/synthetic/unexpected.js', b'extra')
        with self.assertRaisesRegex(vendor.VerificationError, 'unexpected='):
            vendor.verify_repository(self.load(), self.repository)

    def test_modified_missing_and_unexpected_packaged_files(self):
        path = self.bundle / self.bundle_name
        path.write_bytes(b'changed in build')
        with self.assertRaisesRegex(vendor.VerificationError, 'checksum mismatch'):
            vendor.verify_bundle(self.load(), self.bundle, 'linux')
        path.unlink()
        with self.assertRaisesRegex(vendor.VerificationError, 'missing='):
            vendor.verify_bundle(self.load(), self.bundle, 'linux')
        path.write_bytes(self.payload)
        self.write(self.bundle, 'data/flutter_assets/assets/reader/vendor/extra.js', b'extra')
        with self.assertRaisesRegex(vendor.VerificationError, 'unexpected='):
            vendor.verify_bundle(self.load(), self.bundle, 'linux')

    def test_binary_and_notice_bytes_are_not_normalized(self):
        payload = b'\x00\xff\x80\r\napplication-owned binary fixture\r\n'
        manifest = self.load()
        manifest['sha256'][self.name] = vendor.digest(payload)
        path = self.repository / self.name
        path.write_bytes(payload)
        vendor.verify_repository(manifest, self.repository)
        for changed in [payload.decode('utf-8', errors='replace').encode('utf-8'), payload.replace(b'\r\n', b'\n'), payload + b'\n']:
            with self.subTest(changed=changed):
                path.write_bytes(changed)
                with self.assertRaisesRegex(vendor.VerificationError, 'checksum mismatch'):
                    vendor.verify_repository(manifest, self.repository)

    def test_windows_bundle_requires_exact_sdk_notice(self):
        manifest = self.load()
        notice = b'Application-owned synthetic SDK notice\r\n'
        name = 'licenses/webview2-sdk/LICENSE.txt'
        manifest['bundleNotices'] = [{'source': 'synthetic', 'path': 'upstream/LICENSE.txt', 'bundlePath': name, 'sha256': vendor.digest(notice), 'platforms': ['windows']}]
        path = self.write(self.bundle, name, notice)
        vendor.verify_bundle(manifest, self.bundle, 'windows')
        path.write_bytes(notice.replace(b'\r\n', b'\n'))
        with self.assertRaisesRegex(vendor.VerificationError, 'checksum mismatch'):
            vendor.verify_bundle(manifest, self.bundle, 'windows')

    def test_rehashing_local_changes_does_not_establish_upstream_authenticity(self):
        manifest = self.load()
        changed = b'changed local implementation'
        (self.repository / self.name).write_bytes(changed)
        manifest['sha256'][self.name] = vendor.digest(changed)
        vendor.verify_repository(manifest, self.repository)
        with self.assertRaisesRegex(vendor.VerificationError, 'Official archive file differs'):
            vendor.verify_upstream(manifest, {'synthetic': self.archive})

    def test_archive_digest_rejects_wrong_official_input(self):
        self.archive.write_bytes(b'not the official archive')
        with self.assertRaisesRegex(vendor.VerificationError, 'Official archive checksum mismatch'):
            vendor.verify_upstream(self.load(), {'synthetic': self.archive})

    def test_git_files_cannot_be_rehashed_against_unchanged_upstream_blob(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['sources']['synthetic'] = {'kind': 'git', 'url': 'https://example.invalid/synthetic.git', 'revision': 'a' * 40}
        manifest['provenance'][self.name]['gitBlob'] = vendor.git_blob(self.payload)
        manifest = self.load(manifest)
        vendor.verify_repository(manifest, self.repository)
        changed = b'locally modified Git-sourced fixture'
        (self.repository / self.name).write_bytes(changed)
        manifest['sha256'][self.name] = vendor.digest(changed)
        with self.assertRaisesRegex(vendor.VerificationError, 'Upstream Git blob mismatch'):
            vendor.verify_repository(manifest, self.repository)

    def test_symlinked_ancestor_cannot_move_vendor_tree_outside_repository(self):
        outside = self.root / 'outside'
        assets = self.repository / 'assets'
        assets.rename(outside)
        try:
            assets.symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest('Directory symlink creation is unavailable')
        with self.assertRaisesRegex(vendor.VerificationError, 'Linked vendor directory component'):
            vendor.verify_repository(self.load(), self.repository)

    def test_patch_exceptions_and_incomplete_provenance_are_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['modifiedVendorFiles'] = []
        with self.assertRaisesRegex(vendor.VerificationError, 'without vendor modification exceptions'):
            self.load(manifest)
        manifest = copy.deepcopy(self.manifest)
        manifest['provenance'] = {}
        with self.assertRaisesRegex(vendor.VerificationError, 'hash and provenance'):
            self.load(manifest)
        manifest = copy.deepcopy(self.manifest)
        manifest['sources']['synthetic'].pop('release')
        with self.assertRaisesRegex(vendor.VerificationError, 'immutable archive provenance'):
            self.load(manifest)
        manifest = copy.deepcopy(self.manifest)
        manifest['ownedMetadataFiles'] = [self.name]
        with self.assertRaisesRegex(vendor.VerificationError, 'without vendor modification exceptions'):
            self.load(manifest)

    def test_paths_cannot_escape_the_declared_tree(self):
        for name in ['../outside', '/absolute', 'x/../outside', 'x\\outside', 'C:/outside']:
            with self.subTest(name=name), self.assertRaises(vendor.VerificationError):
                vendor.relative(name)

    def test_extracted_build_sources_cannot_be_rewritten(self):
        source = self.manifest['sources']['synthetic']
        extracted = self.root / 'extracted'
        path = self.write(extracted, 'reader.js', self.payload)
        vendor.verify_extracted(source, self.archive, extracted, 'upstream/')
        path.write_bytes(b'build-time rewrite')
        with self.assertRaisesRegex(vendor.VerificationError, 'Modified extracted dependency'):
            vendor.verify_extracted(source, self.archive, extracted, 'upstream/')
        path.write_bytes(self.payload)
        self.write(extracted, 'unexpected.js', b'extra')
        with self.assertRaisesRegex(vendor.VerificationError, 'inventory differs'):
            vendor.verify_extracted(source, self.archive, extracted, 'upstream/')


if __name__ == '__main__':
    unittest.main()
