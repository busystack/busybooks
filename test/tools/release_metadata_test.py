"""Release gates reject invalid identity and history before expensive packaging."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_metadata', REPO / 'tools/release_metadata.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseMetadataTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='busybooks-release-gate-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        current_version = release.versions()[0]
        for name in ['pubspec.yaml', 'pubspec.lock', 'lib/src/app/app_metadata.dart',
                     'snap/snapcraft.yaml', 'packaging/windows/busybooks.iss',
                     'linux/io.busystack.busybooks.metainfo.xml',
                     'tools/vendor-manifest.json']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / name, target)
            if name in {'pubspec.yaml', 'lib/src/app/app_metadata.dart',
                        'snap/snapcraft.yaml', 'packaging/windows/busybooks.iss',
                        'linux/io.busystack.busybooks.metainfo.xml'}:
                target.write_text(target.read_text().replace(current_version, '2.3.4'))
        self.patch = mock.patch.object(release, 'ROOT', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.git('init', '--initial-branch=main')
        self.git('add', '.')
        self.git('-c', 'user.name=Release gate fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-m', 'Owned test fixture')
        self.revision = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', self.revision)
        self.git('tag', 'v2.3.4')  # Disposable fixture repository only.
        self.event_path = self.root / 'event.json'
        self.event_path.write_text('{}')
        self.environment = mock.patch.dict(os.environ, {
            'GITHUB_EVENT_NAME': 'push', 'GITHUB_EVENT_PATH': str(self.event_path),
            'GITHUB_REF': 'refs/tags/v2.3.4', 'GITHUB_REF_TYPE': 'tag',
            'GITHUB_SHA': self.revision,
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root,
                                       stderr=subprocess.PIPE, text=True).strip()

    def test_final_tag_requires_matching_source_versions_and_main_history(self):
        result = release.context(check_event=True)
        self.assertEqual(result['sourceRevision'], self.revision)
        self.assertEqual(result['artifactPrefix'], 'v2.3.4')
        self.assertFalse(result['approved'])

    def test_nonfinal_or_malformed_tags_are_rejected(self):
        for tag in ['v2.3.4-rc.1', 'v2.3.4+1', 'v02.3.4', 'v0.01.0',
                    'v0.1', 'v2.3.4-extra', '2.3.4', 'v2.3.4\n']:
            with self.subTest(tag=tag), mock.patch.dict(os.environ, {'GITHUB_REF': 'refs/tags/' + tag}):
                with self.assertRaisesRegex(ValueError, 'Semantic Versioning'):
                    release.context(check_event=True)

    def test_ordinary_push_is_rejected(self):
        with mock.patch.dict(os.environ, {'GITHUB_REF_TYPE': 'branch', 'GITHUB_REF': 'refs/heads/main'}):
            with self.assertRaisesRegex(ValueError, 'Semantic Versioning'):
                release.context(check_event=True)

    def test_tag_version_mismatch_is_rejected(self):
        with mock.patch.dict(os.environ, {'GITHUB_REF': 'refs/tags/v2.4.0'}):
            with self.assertRaisesRegex(ValueError, 'does not match'):
                release.context(check_event=True)

    def test_release_branch_commit_outside_main_is_rejected(self):
        self.git('checkout', '-b', 'next-release')
        (self.root / 'change').write_text('Owned fixture update')
        self.git('add', 'change')
        self.git('-c', 'user.name=Release gate fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-m', 'Not accepted on main')
        self.git('tag', '-f', 'v2.3.4')
        with mock.patch.dict(os.environ, {'GITHUB_SHA': self.git('rev-parse', 'HEAD')}):
            with self.assertRaises(subprocess.CalledProcessError):
                release.context(check_event=True)

    def test_checked_out_commit_must_equal_tag(self):
        other = 'a' * 40
        self.git('tag', '-d', 'v2.3.4')
        with self.assertRaises(subprocess.CalledProcessError):
            release.context(check_event=True)
        with mock.patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'local', 'GITHUB_SHA': other}):
            with self.assertRaisesRegex(ValueError, 'workflow source revision'):
                release.context()

    def test_candidate_preserves_both_head_and_tested_revision(self):
        head = 'b' * 40
        self.event_path.write_text(json.dumps({'number': 42, 'pull_request': {
            'body': 'Reviewed “candidate” — 中文',
            'base': {'ref': 'main', 'sha': self.revision}, 'head': {'sha': head}}},
            ensure_ascii=False), encoding='utf-8')
        with mock.patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'pull_request'}):
            result = release.context(check_event=True)
        self.assertEqual(result['headRevision'], head)
        self.assertEqual(result['sourceRevision'], self.revision)
        self.assertEqual(result['artifactPrefix'], 'candidate-pr-42-' + head[:12])
        self.assertEqual(result['classification'], 'UNAPPROVED CANDIDATE')

    def test_every_packaging_version_must_agree(self):
        for filename in ['lib/src/app/app_metadata.dart', 'snap/snapcraft.yaml',
                         'packaging/windows/busybooks.iss', 'linux/io.busystack.busybooks.metainfo.xml']:
            with self.subTest(filename=filename):
                path = self.root / filename
                before = path.read_text()
                path.write_text(before.replace('2.3.4', '2.4.0'))
                with self.assertRaisesRegex(ValueError, 'differs from pubspec'):
                    release.versions()
                path.write_text(before)


class ToolchainMetadataTest(unittest.TestCase):
    def setUp(self):
        self.version = dict(frameworkVersion=release.FLUTTER, dartSdkVersion=release.DART,
                            frameworkRevision=release.REVISION)

    def test_cold_start_bootstrap_is_separate_from_machine_json(self):
        ready = False

        def bootstrap(command, **kwargs):
            nonlocal ready
            ready = '--machine' not in command

        def output(command, **kwargs):
            if command[0] == 'git':
                return ''
            return json.dumps(self.version) if ready else 'Building flutter tool...\n'

        with mock.patch.object(release.shutil, 'which', return_value='/owned-sdk/bin/flutter'), \
             mock.patch.object(release.subprocess, 'run', side_effect=bootstrap), \
             mock.patch.object(release.subprocess, 'check_output', side_effect=output):
            self.assertEqual(release.toolchain(), self.version)

    def test_invalid_machine_output_fails_with_diagnostics(self):
        with mock.patch.object(release.shutil, 'which', return_value='/owned-sdk/bin/flutter'), \
             mock.patch.object(release.subprocess, 'run'), \
             mock.patch.object(release.subprocess, 'check_output', return_value='unexpected bootstrap text'):
            with self.assertRaisesRegex(ValueError, 'unexpected bootstrap text'):
                release.toolchain()


if __name__ == '__main__':
    unittest.main()
