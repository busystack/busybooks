# Verify hosted prerequisites and obtain the exact official runtime variants.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$evidence = Join-Path $PWD 'build/release/windows'
New-Item -ItemType Directory -Force $evidence | Out-Null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (!(Test-Path $vswhere)) { throw 'Official Visual Studio Installer/vswhere is required' }
$components = @('Microsoft.VisualStudio.Component.VC.Tools.x86.x64', 'Microsoft.VisualStudio.Component.VC.CMake.Project', 'Microsoft.VisualStudio.Component.VC.ATL')
$install = & $vswhere -latest -products '*' -requires $components -property installationPath
if (!$install) {
    $install = & $vswhere -latest -products '*' -property installationPath
    if (!$install) { throw 'No Visual Studio installation is available' }
    $setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
    $arguments = @('modify', '--installPath', "`"$install`"", '--quiet', '--norestart', '--wait')
    foreach ($component in $components) { $arguments += @('--add', $component) }
    $process = Start-Process $setup -ArgumentList $arguments -PassThru -Wait
    if ($process.ExitCode -notin @(0, 3010)) { throw "Visual Studio component installation failed: $($process.ExitCode)" }
}
$verified = & $vswhere -latest -products '*' -requires $components -format json
$verified | Set-Content "$evidence/visual-studio.json"
if (!($verified | ConvertFrom-Json)) { throw 'Required MSVC, CMake and ATL components are missing' }
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\Include" -Directory |
    Where-Object { (Test-Path (Join-Path $_.FullName 'um\Windows.h')) -and (Test-Path (Join-Path $_.FullName 'ucrt\stdio.h')) }
if (!$sdk) { throw 'A complete Windows SDK (UM and UCRT headers) is required' }
$sdk.FullName | Set-Content "$evidence/windows-sdk.txt"
foreach ($tool in 'cmake', 'python', 'node', 'git') { Get-Command $tool -ErrorAction Stop | Out-String | Add-Content "$evidence/build-tools.txt" }
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (!(Test-Path $iscc)) { throw 'Official Inno Setup 6 is required on the Windows runner' }
(Get-Item $iscc).VersionInfo | Format-List | Out-File "$evidence/inno-setup.txt"
"BUSYBOOKS_ISCC=$iscc" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV
$downloads = Join-Path $env:RUNNER_TEMP 'busybooks-runtimes'
New-Item -ItemType Directory -Force $downloads | Out-Null
$records = @()
foreach ($item in @(
    @{name='MicrosoftEdgeWebView2RuntimeInstallerX64.exe'; url='https://go.microsoft.com/fwlink/p/?LinkId=2124701'},
    @{name='VC_redist.x64.exe'; url='https://aka.ms/vc14/vc_redist.x64.exe'}
)) {
    $file = Join-Path $downloads $item.name
    Invoke-WebRequest -Uri $item.url -OutFile $file -MaximumRedirection 10
    $signature = Get-AuthenticodeSignature $file
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        throw "Invalid Microsoft signature: $file"
    }
    $records += [ordered]@{name=$item.name; url=$item.url; sha256=(Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant(); signer=$signature.SignerCertificate.Subject; certificate=$signature.SignerCertificate.Thumbprint; version=(Get-Item $file).VersionInfo.ProductVersion}
}
$records | ConvertTo-Json -Depth 5 | Set-Content "$evidence/runtime-downloads.json"
"BUSYBOOKS_RUNTIME_DIRECTORY=$downloads" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV
