param(
    [Parameter(Mandatory = $true)][string]$FlutterSdk,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][string]$SourceRevision,
    [string]$SourceDirectory = ''
)

# Run on Windows, with the official pinned SDK and the existing lockfile.
# The Win32 menu probe also requires an unlocked interactive desktop.
$ErrorActionPreference = 'Stop'
$source = if ($SourceDirectory) { (Resolve-Path $SourceDirectory).Path } else { Split-Path -Parent $PSScriptRoot }
Set-Location $source
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$FlutterSdk = (Resolve-Path $FlutterSdk).Path
New-Item -ItemType Directory -Force $EvidenceDirectory | Out-Null
$EvidenceDirectory = (Resolve-Path $EvidenceDirectory).Path
$flutter = Join-Path $FlutterSdk 'bin\flutter.bat'
$dart = Join-Path $FlutterSdk 'bin\dart.bat'
$report = [ordered]@{
    sourceRevision = $SourceRevision
    startedUtc = [DateTime]::UtcNow.ToString('o')
    platform = [Environment]::OSVersion.VersionString
    sessionId = (Get-Process -Id $PID).SessionId
    flutterSdk = $FlutterSdk
    checks = @()
}

function Invoke-Check([string]$Name, [string]$Executable, [string[]]$Arguments) {
    $log = Join-Path $EvidenceDirectory ($Name + '.log')
    $start = [DateTime]::UtcNow
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $command = Get-Command $Executable -ErrorAction SilentlyContinue
    if ($command) {
        & $command @Arguments 2>&1 | ForEach-Object { $_.ToString() } | Out-File -Encoding utf8 $log
        $code = $LASTEXITCODE
    } else {
        "Required executable unavailable: $Executable" | Out-File -Encoding utf8 $log
        $code = 127
    }
    $ErrorActionPreference = $oldPreference
    $report.checks += [ordered]@{
        name = $Name
        command = @($Executable) + $Arguments
        exitCode = $code
        startedUtc = $start.ToString('o')
        finishedUtc = [DateTime]::UtcNow.ToString('o')
        log = $log
        sha256 = (Get-FileHash $log -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory 'automated-results.json')
    Write-Output "$Name exit=$code"
    return ($code -eq 0)
}

$versionLog = Join-Path $EvidenceDirectory 'flutter-version.json'
& $flutter --version --machine | Out-File -Encoding utf8 $versionLog
if ($LASTEXITCODE -ne 0) { throw 'Flutter version check failed' }
$version = Get-Content $versionLog -Raw | ConvertFrom-Json
if ($version.frameworkVersion -ne '3.47.5' -or $version.dartSdkVersion -notlike '3.13.4*' -or
    $version.frameworkRevision -ne '6a19cca56475dbfba1478ee68d7bd0c2ef891da1') {
    throw 'Qualification requires the official pinned Flutter 3.47.5 / Dart 3.13.4 SDK'
}
$report.toolchain = $version
$lockBefore = (Get-FileHash pubspec.lock -Algorithm SHA256).Hash
$null = Invoke-Check 'doctor' $flutter @('doctor', '-v')
$null = Invoke-Check 'devices' $flutter @('devices')
if (!(Invoke-Check 'dependencies' $flutter @('pub', 'get', '--enforce-lockfile') | Select-Object -Last 1)) {
    throw 'Locked dependency resolution failed'
}
$null = Invoke-Check 'localization' $flutter @('gen-l10n')
$null = Invoke-Check 'format' $dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tools')
$null = Invoke-Check 'analysis' $flutter @('analyze')
$null = Invoke-Check 'tests' $flutter @('test', '--machine')
foreach ($probe in 'storage', 'cache', 'annotation_order') {
    $null = Invoke-Check $probe $dart @('run', "tools/${probe}_probe.dart")
}
$build = Invoke-Check 'windows-release' $flutter @('build', 'windows', '--release') | Select-Object -Last 1
if ($build) {
    $release = Join-Path $source 'build\windows\x64\runner\Release'
    $env:BUSYBOOKS_COMIC_DECODER = Join-Path $release 'busybooks_comic_archive.exe'
    $null = Invoke-Check 'rar' 'python.exe' @('tools/qualify_rar.py', $env:BUSYBOOKS_COMIC_DECODER)
    $null = Invoke-Check 'formats' $dart @('run', 'tools/format_probe.dart')
    $null = Invoke-Check 'format-resources' $dart @('run', 'tools/format_resources_probe.dart')
    foreach ($probe in 'font', 'menu') {
        $directory = "build/native-$probe-probe"
        $configured = Invoke-Check "$probe-configure" 'cmake.exe' @('-S', "tools/native_${probe}_probe", '-B', $directory) | Select-Object -Last 1
        if ($configured) {
            $compiled = Invoke-Check "$probe-build" 'cmake.exe' @('--build', $directory, '--config', 'Release') | Select-Object -Last 1
            if ($compiled) {
                $null = Invoke-Check "$probe-native" (Join-Path $source "$directory/Release/busybooks_native_${probe}_probe.exe") @()
                if ($probe -eq 'menu') {
                    $null = Invoke-Check 'menu-selection' (Join-Path $source "$directory/Release/busybooks_menu_selection_test.exe") @()
                }
            }
        }
    }
    $report.releaseFiles = @(Get-ChildItem $release -File -Recurse | ForEach-Object {
        [ordered]@{path = $_.FullName.Substring($release.Length + 1); bytes = $_.Length; sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
}
$null = Invoke-Check 'reader-javascript' 'node.exe' @('tools/reader_logic_probe.mjs')
if ((Get-FileHash pubspec.lock -Algorithm SHA256).Hash -ne $lockBefore) {
    throw 'Dependency lockfile changed during qualification'
}
$report.lockfileUnchanged = $true
$report.finishedUtc = [DateTime]::UtcNow.ToString('o')
$report.passed = (@($report.checks | Where-Object { $_.exitCode -ne 0 }).Count -eq 0)
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $EvidenceDirectory 'automated-results.json')
if (!$report.passed) { throw 'Windows qualification contains failures; inspect automated-results.json and logs' }
