# Release verification and acceptance

`main` contains accepted releases. Development stays on other branches. Open a
**draft pull request into main** to qualify a release without merging it.
[desktop.yml](../../.github/workflows/desktop.yml) runs on PR opened, synchronize,
reopened and ready-for-review events, and pushes of `v*` tags. There are no branch
push, schedule, dispatch, release-publishing or Snap Store-publishing triggers.
A broad tag filter only starts validation: the identity gate accepts exactly
`vMAJOR.MINOR.PATCH`, without leading zeroes, prerelease or build suffixes.

A workflow in an eligible PR can run before it exists on the default branch.
Manual workflow dispatch has a separate default-branch requirement and is not
used here. See GitHub's [event semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
and [branch/tag filters](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushbranchestagsbranches-ignoretags-ignore).
Fork PRs may require a maintainer to approve execution under repository settings;
no secrets or write token are supplied to builds.

## Automated gates

| Job | Required work |
| --- | --- |
| Release identity | Match pubspec, Dart metadata, Snap and Inno versions and pinned Flutter configuration. Final tags must match the version and resolve to a commit in `origin/main` history. |
| Linux verification | Official Flutter 3.47.5 revision / Dart 3.13.4; locked packages; every Python test; format/analyze/Flutter tests; normative EPUB 2; SQLite/storage/cache/order/cross-volume; release compilation; vendor/build-source inventory; MIME/RAR/formats/resources; reader JS; GTK/input/WebKit/typography/formats/review/Chromium; bundled application opening. |
| Windows verification and installer | Check MSVC/CMake/ATL/SDK/Inno prerequisites, official pinned SDK, all applicable Python tests, format/analyze/Flutter tests, storage/cache/order, release compilation, unchanged WebView2/UnRAR build inputs, decoder/formats/resources, DirectWrite and native menus, reader JS; stage exact verified build; signed Microsoft offline runtimes; ZIP and Inno installer; installed bytes, version/architecture/assets, associations, native-window startup, uninstall. |
| Snap packaging and installation | Canonical's maintained LXD/Snapcraft build, core24; inspect generated metadata, ELF/assets/libraries/vendor bytes/desktop/MIME; install with strict confinement; verify mounted bytes; existing 19-book rendering/opening/location probe under Xvfb through the home interface; removal. |
| Release verification complete | Always runs and fails unless every preceding mandatory job succeeded, including packaging and artifact upload. Require this exact check on main. |

Linux's ordinary build qualifies host-native probes; Snapcraft independently
compiles against its isolated core24 environment. Windows packaging reuses the
qualified build only after checking source, lockfile and every release file hash.
A failed or skipped required check cannot become a successful aggregate result.
There is no `continue-on-error`.

`python -m unittest discover -v -s test/tools -p '*_test.py'` is the shared Python
entry. `LinuxDesktopInstallTest` explicitly requires Linux XDG/executable/path
semantics; `LinuxShutdownProbeTest` explicitly requires Linux processes/signals/X11.
Windows reports these eight cases as skipped with reasons. Linux runs all eight,
including actual GIO and GTK cache checks. Typography, vendor integrity and release
identity tests run on both platforms. Vendor's directory symlink test reports an
explicit capability skip if OS permissions prevent creation. No assertions or
fixtures were relaxed.

## Artifacts and provenance

PR artifacts use `candidate-pr-N-HEADSHA12-*`; they are **unapproved candidates**.
The provenance records both the PR head and the tested GitHub merge revision.
Final artifacts use `vMAJOR.MINOR.PATCH-*`. Neither name implies manual acceptance.
Each package artifact includes verification evidence, its SHA-256 sidecar, source
revision, run URL/attempt, toolchain and checked-in lockfile/vendor manifest.
Snapcraft's build manifest also records staged package versions.

Expected package files for the declared source version:

- `busybooks_VERSION_amd64.snap`
- `BusyBooks-VERSION-windows-x64.exe`
- `busybooks-VERSION-windows-x64.zip`
- A `.sha256` file for each package.

Use the workflow run's **Artifacts** section to download (30-day retention).
Diagnostics artifacts are separate, may contain failed checks, and are never
qualified distributions. Uploads of package artifacts occur only after validation.
Checks assert individual required files exist; upload also uses
`if-no-files-found: error`. Download and verify sidecars with `sha256sum -c` on
Linux or `Get-FileHash -Algorithm SHA256` on Windows. Artifact ZIP hashes shown by
GitHub describe the artifact archive, not the enclosed installer or Snap.

The Snap remains `grade: devel`, `confinement: strict`, core24/amd64. Local install
uses `--dangerous` solely because the candidate has no Store assertion; it does
not use `--devmode` or `--classic`. Grade changes require release-owner approval.
The Inno installer retains the application ID, per-user destination, optional
associations and uninstall registration. Visual C++ is a Microsoft system runtime
and can need administrator consent even though BusyBooks itself installs per user.
WebView2 uses the Evergreen **standalone x64 offline installer**, not its online
bootstrapper or Fixed Version runtime. Microsoft signatures are mandatory; hashes,
certificate identity and downloaded product versions are recorded. The app SDK
remains independently pinned by its NuGet archive hash.

The application installer is currently unsigned; package checksums establish the
built bytes, not publisher code-signing identity. No signing identity is invented.

## Protect main before accepting a release

Import [.github/main-ruleset.json](../../.github/main-ruleset.json) in repository
Settings → Rules → Rulesets → New ruleset → Import a ruleset. Alternatively create
an **active branch ruleset** named `Accepted releases on main` with:

- Include `refs/heads/main`, no exclusions and no bypass actors (including admins).
- Restrict deletions and block force pushes.
- Require a pull request, one approving reviewer, dismiss stale approvals, require
  approval from someone other than the last pusher, and resolve review threads.
- Require `Release verification complete`, source **GitHub Actions**, and require
  the branch to be up to date. Do not add skipped interactive checks as required
  contexts or enable merge queue without adding its separate event support.

The PR requirement prevents direct pushes while permitting reviewed merges.
Do not enable the separate “Restrict updates” rule: with no bypass actor it would
also forbid accepted PR merges. See [GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets).
An independent reviewer must record installed-package acceptance for the exact
head revision and artifact hashes before approving. New commits dismiss approval.
The aggregate check verifies automation; review records human acceptance.

An administrator can also apply the file with the authenticated GitHub CLI:
`gh api --method POST repos/busystack/busybooks/rulesets --input .github/main-ruleset.json`.
Inspect existing rulesets first and update an existing rule by ID instead of
creating duplicates. Committing the JSON alone does **not** activate protection.
Confirm the active rule in Settings and verify direct pushes/force pushes/deletion
are blocked without attempting a destructive operation against main.

## Installed-package acceptance (required before merging)

Record OS/version, hardware/display, source/head/tested revisions, package SHA-256,
steps, outcomes and diagnostics in the PR acceptance record. Always use copied
fixtures and a disposable profile; retain evidence outside maintained source.
Automated startup or native reader probes do not establish this full acceptance.

### Linux strict Snap

On a disposable supported Ubuntu 24.04 desktop with snapd, download the candidate,
verify SHA-256, then run:

```sh
sudo snap install --dangerous busybooks_VERSION_amd64.snap
snap info busybooks
snap connections busybooks
snap run busybooks
# If testing external media, explicitly connect this non-auto-connected interface:
sudo snap connect busybooks:removable-media
```

Confirm strict confinement, the BusyBooks name/icon and desktop app identity
`io.busystack.busybooks`. Launch through the installed desktop entry. Open copied
EPUB 2/3, PDF, raw/wrapped FB2, CBZ and CBR through command-line forwarding, chooser
and drops from ordinary home directories. Confirm rendering, bookmarks, highlights,
notes, saved locations and reopening after restart. Test the real desktop portal
and chooser, both X11 and Wayland where supported, icon/MIME integration, clipboard,
fonts, speech, GPU/display scaling, Split/modal focus and offline reading.

Test an external removable volume before and after interface connection; confirm
access follows the declared plug. Verify denied paths remain denied (including
unrelated hidden home data); do not grant classic/devmode access to fix a failure.
Exercise original-byte export, Move/Locate, cache deletion, collection and backup
restore using [existing acceptance procedures](../../tools/README.md).
Finish with `sudo snap remove --purge busybooks` and inspect cleanup. The Xvfb CI
probe only establishes its tested headless X11 paths and home access.

### Windows x64 Inno installer

Use a disposable supported Windows desktop as a standard user. Verify checksums,
install with default options, confirm the per-user destination and uninstall entry,
and opt into each file-association task. Repeat on a clean machine without runtimes
and without network: the bundled Microsoft installers must provide the required
WebView2/VC runtimes. Record administrator consent/reboot requirements for VC;
BusyBooks files and associations must remain per user. Also test a machine with
newer Microsoft runtimes already installed. Do not substitute a runtime variant.

Check complete resources, SQLite/plugins, decoder and notices. Launch Home, then
exercise all book formats through the chooser, associations, drops and forwarded
paths. Perform [Windows GUI qualification](windows.md#reproducible-qualification)
and the shared [Split acceptance procedure](../../tools/README.md#split-workspace-acceptance),
including WebView2 rendering/selection, keyboard/menus, fonts, dialogs, 100/150/200%
scaling, restart/cache/backup behavior and offline operation. Close cleanly, uninstall,
verify associations/shortcuts/application removal, and confirm user documents and
shared Microsoft runtimes are preserved. Hosted-runner installation/native-window
startup does not establish clean unelevated runtime installation or these GUI checks.

## Accepted release and manual publication

After successful automation and recorded installed-package acceptance, an authorized
maintainer may approve and merge the PR. **This implementation task does not merge.**
Only after acceptance, the owner tags the accepted main commit with the exact
`vVERSION`. The tag invokes the same verification and packaging jobs and validates
main ancestry and source versions. Do not create release-candidate tags.

Final-tag execution remains unverified until that approved release action actually
occurs. Inspect/download the final artifacts, verify checksums and provenance, and
accept those package bytes. Candidate packages are never automatically promoted.
The owner then creates/publishes the GitHub Release and handles Snap Store upload
manually. Neither workflow nor helper has publication credentials or publication
commands. A `devel` Snap is not eligible for stable/candidate Store channels until
an independently approved grade change.

## Upstream references

- [Canonical action-build implementation](https://github.com/snapcore/action-build/blob/3bdaa03e1ba6bf59a65f84a751d943d549a54e79/src/build.ts): maintained LXD provider and output Snap path.
- [Snapcraft bases](https://documentation.ubuntu.com/snapcraft/stable/reference/bases/), [GNOME extension](https://documentation.ubuntu.com/snapcraft/stable/reference/extensions/gnome-extension/).
- [Flutter Linux distribution](https://docs.flutter.dev/platform-integration/linux/building), [Windows prerequisites](https://docs.flutter.dev/platform-integration/windows/setup).
- [Microsoft WebView2 distribution](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution), [VC runtime distribution](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
- [Inno compiler](https://jrsoftware.org/ishelp/topic_compilercmdline.htm), [silent setup](https://jrsoftware.org/ishelp/topic_setupcmdline.htm), [setup events](https://jrsoftware.org/ishelp/topic_scriptevents.htm).
- [GitHub artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data).
