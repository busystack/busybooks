param(
  [Parameter(Mandatory=$true)][string]$WebViewRuntimeInstaller,
  [Parameter(Mandatory=$true)][string]$VisualCppRuntimeInstaller,
  [string]$QualificationDirectory = '',
  [string]$InnoCompiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$WebViewRuntimeInstaller = (Resolve-Path $WebViewRuntimeInstaller).Path
$VisualCppRuntimeInstaller = (Resolve-Path $VisualCppRuntimeInstaller).Path
foreach ($file in @($WebViewRuntimeInstaller, $VisualCppRuntimeInstaller)) {
    $signature = Get-AuthenticodeSignature $file
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        throw "Runtime installer must have a valid Microsoft signature: $file"
    }
}
if (!$QualificationDirectory) {
    $QualificationDirectory = Join-Path $PWD 'build/release/windows'
    $sdk = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
    & ./tools/qualify_windows.ps1 -FlutterSdk $sdk -EvidenceDirectory $QualificationDirectory -SourceRevision (git rev-parse HEAD)
}
$report = Get-Content (Join-Path $QualificationDirectory 'automated-results.json') -Raw | ConvertFrom-Json
if (!$report.passed -or !$report.lockfileUnchanged -or $report.sourceRevision -ne (git rev-parse HEAD)) {
    throw 'Packaging requires successful qualification of this exact source revision'
}
if ((Get-FileHash pubspec.lock -Algorithm SHA256).Hash -ne $report.lockfileSha256) { throw 'Lockfile changed since qualification' }
$release = Join-Path $PWD 'build/windows/x64/runner/Release'
$actual = @(Get-ChildItem $release -File -Recurse)
if (!$report.releaseFiles -or $actual.Count -ne $report.releaseFiles.Count) { throw 'Qualified release inventory differs' }
foreach ($file in $report.releaseFiles) {
    if ((Get-FileHash (Join-Path $release $file.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
        throw "Qualified build changed: $($file.path)"
    }
}
$metadata = python tools/release_metadata.py --toolchain | ConvertFrom-Json
if ($LASTEXITCODE) { throw 'Release metadata/toolchain validation failed' }
$staging = Join-Path $PWD 'build/distributions/windows'
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force $staging | Out-Null
Copy-Item "$release/*" $staging -Recurse -Force
Copy-Item $WebViewRuntimeInstaller (Join-Path $staging 'MicrosoftEdgeWebView2RuntimeInstallerX64.exe') -Force
Copy-Item $VisualCppRuntimeInstaller (Join-Path $staging 'VC_redist.x64.exe') -Force
Copy-Item LICENSE,NOTICE,'docs/development/windows.md' $staging
python tools/verify_vendor.py --platform windows --bundle $staging
if ($LASTEXITCODE) { throw 'Staged vendor verification failed' }
python tools/verify_distribution.py --platform windows --bundle $staging --output (Join-Path $QualificationDirectory 'staged-distribution.json')
if ($LASTEXITCODE) { throw 'Staged distribution verification failed' }
$zip = Join-Path $PWD "build/distributions/busybooks-$($metadata.version)-windows-x64.zip"
Compress-Archive -Path "$staging/*" -DestinationPath $zip -Force
if (!(Test-Path $InnoCompiler)) { throw "Inno Setup compiler is missing: $InnoCompiler" }
$output = Join-Path $PWD 'build/distributions'
& $InnoCompiler "/O$output" 'packaging/windows/busybooks.iss' 2>&1 | Tee-Object -FilePath (Join-Path $QualificationDirectory 'inno-build.log')
if ($LASTEXITCODE) { throw 'Inno Setup compilation failed' }
$installer = Join-Path $output "BusyBooks-$($metadata.version)-windows-x64.exe"
if (!(Test-Path $installer)) { throw "Required installer missing: $installer" }
foreach ($package in @($zip, $installer)) {
    $hash = (Get-FileHash $package -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path -Leaf $package)" | Set-Content -Encoding ascii "$package.sha256"
}
Write-Output $installer
