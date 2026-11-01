#!/usr/bin/env python3
"""Validate release identity without rewriting source; record artifact provenance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
FLUTTER = '3.47.5'
DART = '3.13.4'
REVISION = '6a19cca56475dbfba1478ee68d7bd0c2ef891da1'


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def match(path, pattern):
    values = re.findall(pattern, (ROOT / path).read_text(encoding='utf-8'), re.M)
    if len(values) != 1:
        raise ValueError(f'{path}: expected exactly one version declaration')
    return values[0]


def versions():
    package = match('pubspec.yaml', rf'^version: ({VERSION}\+[0-9]+)\s*$')
    version, build = package.split('+')
    declared = {
        'Dart application': match('lib/src/app/app_metadata.dart', r"^const busyBooksAppVersion = '([^']+)';$"),
        'Snap': match('snap/snapcraft.yaml', r"^version: '([^']+)'$"),
        'Inno Setup': match('packaging/windows/busybooks.iss', r'^#define MyAppVersion "([^"]+)"$'),
    }
    for source, value in declared.items():
        if value != version:
            raise ValueError(f'{source} version {value!r} differs from pubspec {version!r}')
    if match('pubspec.yaml', r'^  flutter: (\S+)$') != FLUTTER:
        raise ValueError('pubspec Flutter constraint differs from the pinned toolchain')
    if match('snap/snapcraft.yaml', r"^      - BUSYBOOKS_FLUTTER_VERSION: '([^']+)'$") != FLUTTER:
        raise ValueError('Snap Flutter toolchain differs from the release toolchain')
    return version, build


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT, encoding='utf-8').strip()


def context(check_event=False):
    version, build = versions()
    revision = git('rev-parse', 'HEAD')
    event_name = os.environ.get('GITHUB_EVENT_NAME', 'local')
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text(encoding='utf-8')) if os.environ.get('GITHUB_EVENT_PATH') else {}
    result = dict(version=version, buildNumber=build, sourceRevision=revision,
                  lockfileSha256=sha256(ROOT / 'pubspec.lock'),
                  vendorManifestSha256=sha256(ROOT / 'tools/vendor-manifest.json'),
                  event=event_name, approved=False)
    if event_name == 'pull_request':
        pr = event['pull_request']
        if pr['base']['ref'] != 'main':
            raise ValueError('Release candidates require a pull request targeting main')
        result.update(pullRequest=event['number'], headRevision=pr['head']['sha'],
                      baseRevision=pr['base']['sha'], classification='UNAPPROVED CANDIDATE',
                      artifactPrefix=f"candidate-pr-{event['number']}-{pr['head']['sha'][:12]}")
    elif event_name == 'push':
        tag = os.environ.get('GITHUB_REF', '').removeprefix('refs/tags/')
        if os.environ.get('GITHUB_REF_TYPE') != 'tag' or not re.fullmatch('v' + VERSION, tag):
            raise ValueError('Final release requires a stable Semantic Versioning tag vMAJOR.MINOR.PATCH (no prerelease/build suffix)')
        if tag != 'v' + version:
            raise ValueError(f'Tag {tag!r} does not match application version v{version}')
        if git('rev-parse', f'{tag}^{{commit}}') != revision:
            raise ValueError('Checkout is not the tagged commit')
        subprocess.run(['git', 'merge-base', '--is-ancestor', revision, 'origin/main'], cwd=ROOT, check=True)
        result.update(tag=tag, acceptedMainRevision=git('rev-parse', 'origin/main'),
                      classification='FINAL BUILD; MANUAL PUBLICATION REQUIRED', artifactPrefix=tag)
    elif check_event:
        raise ValueError(f'Unsupported release event: {event_name}')
    else:
        result.update(classification='LOCAL CHECK', artifactPrefix=f'local-{revision[:12]}')
    if os.environ.get('GITHUB_SHA') and revision != os.environ['GITHUB_SHA']:
        raise ValueError('Checkout differs from the workflow source revision')
    result.update(runUrl=f"https://github.com/{os.environ.get('GITHUB_REPOSITORY', 'busystack/busybooks')}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}",
                  runAttempt=os.environ.get('GITHUB_RUN_ATTEMPT'), platform=platform.platform(),
                  python=platform.python_version())
    return result


def toolchain():
    flutter = shutil.which('flutter')
    if not flutter:
        raise ValueError('Flutter is required')
    # The official Windows archive bootstraps flutter_tools on its first command.
    # Keep that command's human-readable output out of the machine JSON stream.
    subprocess.run([flutter, '--version'], check=True, stdout=sys.stderr)
    output = subprocess.check_output([flutter, '--version', '--machine'], encoding='utf-8')
    try:
        data = json.loads(output)
    except json.JSONDecodeError as error:
        raise ValueError(f'Flutter machine output is not JSON: {output[:2000]}') from error
    if (data['frameworkVersion'], data['dartSdkVersion'].split()[0], data['frameworkRevision']) != (FLUTTER, DART, REVISION):
        raise ValueError(f'Expected official Flutter {FLUTTER} ({REVISION}) / Dart {DART}; got {data}')
    # Detect modifications to tracked SDK sources as well as a misleading version label.
    sdk = Path(flutter).resolve().parent.parent
    if subprocess.check_output(['git', '-C', str(sdk), 'status', '--porcelain', '--untracked-files=no'], encoding='utf-8').strip():
        changes = subprocess.check_output(['git', '-C', str(sdk), 'diff', '--stat'], encoding='utf-8')
        raise ValueError(f'Tracked Flutter SDK sources have been modified: {changes}')
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-event', action='store_true')
    parser.add_argument('--github-output', action='store_true')
    parser.add_argument('--toolchain', action='store_true')
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--package', type=Path)
    args = parser.parse_args()
    try:
        data = context(args.check_event)
        if args.toolchain:
            data['toolchain'] = toolchain()
        if args.package:
            package = args.package.resolve(strict=True)
            if package.stat().st_size == 0:
                raise ValueError(f'Empty release package: {package}')
            data['package'] = dict(name=package.name, bytes=package.stat().st_size, sha256=sha256(package))
            package.with_name(package.name + '.sha256').write_text(f'{sha256(package)}  {package.name}\n', encoding='utf-8')
        if args.evidence:
            args.evidence.mkdir(parents=True, exist_ok=True)
            (args.evidence / 'provenance.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
            shutil.copyfile(ROOT / 'pubspec.lock', args.evidence / 'pubspec.lock')
            shutil.copyfile(ROOT / 'tools/vendor-manifest.json', args.evidence / 'vendor-manifest.json')
        if args.github_output:
            with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
                output.write(f"version={data['version']}\nprefix={data['artifactPrefix']}\n")
        print(json.dumps(data, indent=2))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Release validation failed: {error}\n')


if __name__ == '__main__':
    main()
