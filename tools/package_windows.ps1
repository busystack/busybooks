param(
  [Parameter(Mandatory=$true)][string]$WebViewRuntimeInstaller,
  [Parameter(Mandatory=$true)][string]$VisualCppRuntimeInstaller
)
$ErrorActionPreference='Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$flutterVersion=(flutter --version --machine | ConvertFrom-Json).frameworkVersion
if ($flutterVersion -ne '3.47.5') {throw 'Flutter 3.47.5 is required.'}
if (!(Test-Path $WebViewRuntimeInstaller)) {throw 'Supply the official Evergreen standalone WebView2 Runtime installer for offline installation.'}
$signature=Get-AuthenticodeSignature $WebViewRuntimeInstaller
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {throw 'WebView2 Runtime installer must have a valid Microsoft signature.'}
if (!(Test-Path $VisualCppRuntimeInstaller)) {throw 'Supply the official Microsoft Visual C++ x64 redistributable installer.'}
$vcSignature=Get-AuthenticodeSignature $VisualCppRuntimeInstaller
if ($vcSignature.Status -ne 'Valid' -or $vcSignature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {throw 'Visual C++ runtime installer must have a valid Microsoft signature.'}
flutter clean
if ($LASTEXITCODE) {throw 'clean failed'}
flutter pub get --enforce-lockfile
if ($LASTEXITCODE) {throw 'pub get failed'}
flutter gen-l10n
flutter analyze
if ($LASTEXITCODE) {throw 'analysis failed'}
flutter test
if ($LASTEXITCODE) {throw 'tests failed'}
flutter build windows --release
if ($LASTEXITCODE) {throw 'release build failed'}
$staging=Join-Path $PWD 'build/distributions/windows'
if (Test-Path $staging) {Remove-Item -Recurse -Force $staging}
New-Item -ItemType Directory -Force $staging | Out-Null
Copy-Item 'build/windows/x64/runner/Release/*' $staging -Recurse -Force
Copy-Item $WebViewRuntimeInstaller (Join-Path $staging 'MicrosoftEdgeWebView2RuntimeInstallerX64.exe') -Force
Copy-Item $VisualCppRuntimeInstaller (Join-Path $staging 'VC_redist.x64.exe') -Force
Copy-Item LICENSE,NOTICE,'docs/development/windows.md' $staging
$zip=Join-Path $PWD 'build/distributions/busybooks-0.1.0-windows-x64.zip'
Compress-Archive -Path "$staging/*" -DestinationPath $zip -Force
Get-FileHash $zip -Algorithm SHA256 | Format-List | Out-File "$zip.sha256"
Write-Output $zip
