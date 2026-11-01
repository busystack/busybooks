param([Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$Installer = (Resolve-Path $Installer).Path
$evidence = Join-Path $PWD 'build/release/windows'
$staging = Join-Path $PWD 'build/distributions/windows'
$destination = Join-Path $env:RUNNER_TEMP 'busybooks-installed'
function Invoke-Installer([string]$File, [string[]]$Arguments) {
    $process = Start-Process $File -ArgumentList $Arguments -PassThru
    if (!$process.WaitForExit(300000)) { $process.Kill(); throw "Installer timed out: $File" }
    if ($process.ExitCode -ne 0) { throw "Installer failed ($($process.ExitCode)): $File" }
}
Invoke-Installer $Installer @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/SP-', '/NORESTART', "/DIR=`"$destination`"", '/TASKS=epub,pdf,fb2,comics', "/LOG=`"$evidence/install.log`"")
$metadata = python tools/release_metadata.py | ConvertFrom-Json
if ($LASTEXITCODE) { throw 'Invalid release version' }
$version = (Get-Item "$destination/busybooks.exe").VersionInfo.ProductVersion
if ($version -ne "$($metadata.version)+$($metadata.buildNumber)") { throw "Installed executable version differs: $version" }
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\io.busystack.busybooks_is1'
$registration = Get-ItemProperty $uninstallKey
# Inno 6's English NameAndVersion default includes the word "version".
# Keep the existing installer behavior and verify its exact registration.
$registration | Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, UninstallString |
    ConvertTo-Json | Set-Content "$evidence/uninstall-registration.json"
if ($registration.DisplayName -ne "BusyBooks version $($metadata.version)" -or $registration.DisplayVersion -ne $metadata.version) {
    throw "Invalid per-user uninstall registration: name='$($registration.DisplayName)', version='$($registration.DisplayVersion)'"
}
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'BusyBooks\BusyBooks.lnk'
if (!(Test-Path $shortcut)) { throw 'Missing per-user Start Menu shortcut' }
$shell = New-Object -ComObject WScript.Shell
if ($shell.CreateShortcut($shortcut).TargetPath -ne "$destination\busybooks.exe") { throw 'Invalid Start Menu shortcut target' }
foreach ($file in Get-ChildItem $staging -File -Recurse) {
    $relative = $file.FullName.Substring($staging.Length + 1)
    if ((Get-FileHash "$destination/$relative" -Algorithm SHA256).Hash -ne (Get-FileHash $file.FullName -Algorithm SHA256).Hash) {
        throw "Installed bytes differ: $relative"
    }
}
python tools/verify_distribution.py --platform windows --bundle $destination --output "$evidence/installed-distribution.json"
if ($LASTEXITCODE) { throw 'Installed distribution verification failed' }
python tools/qualify_rar.py "$destination/busybooks_comic_archive.exe"
if ($LASTEXITCODE) { throw 'Installed decoder qualification failed' }
$command = (Get-ItemProperty 'HKCU:\Software\Classes\BusyBooks.Book\shell\open\command').'(default)'
if ($command -ne "`"$destination\busybooks.exe`" `"%1`"") { throw "Invalid installed association command: $command" }
foreach ($extension in '.epub', '.pdf', '.fb2', '.fbz', '.cbz', '.cbr') {
    $values = Get-ItemProperty "HKCU:\Software\Classes\$extension\OpenWithProgids"
    if ($values.PSObject.Properties.Name -notcontains 'BusyBooks.Book') { throw "Missing association: $extension" }
}
$env:BUSYBOOKS_PROFILE = Join-Path $env:RUNNER_TEMP 'busybooks-installed-profile'
$fixture = (Resolve-Path 'test/fixtures/reflowable.epub').Path
$app = Start-Process "$destination/busybooks.exe" -ArgumentList "`"$fixture`"" -PassThru -RedirectStandardOutput "$evidence/installed-app.stdout.log" -RedirectStandardError "$evidence/installed-app.stderr.log"
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    do {
        Start-Sleep -Milliseconds 500
        $app.Refresh()
        if ($app.HasExited) { throw "Installed application exited early: $($app.ExitCode)" }
    } until ($app.MainWindowHandle -ne 0 -or [DateTime]::UtcNow -ge $deadline)
    if ($app.MainWindowHandle -eq 0) { throw 'Installed application did not create a native window' }
    # A visible native window establishes startup, not full WebView2 book acceptance.
    $startup = @{pid=$app.Id; nativeWindow=$app.MainWindowHandle.ToInt64(); scope='Installed application created a native window; reader GUI acceptance remains manual'}
    $startup | ConvertTo-Json | Set-Content "$evidence/installed-startup.json"
    if (!$app.CloseMainWindow() -or !$app.WaitForExit(30000)) { throw 'Installed application did not close normally' }
    if ($app.ExitCode -ne 0) { throw "Installed application closed with exit code $($app.ExitCode)" }
} finally {
    if (!$app.HasExited) { Stop-Process -Id $app.Id -Force; $app.WaitForExit() }
    Remove-Item Env:BUSYBOOKS_PROFILE
}
Invoke-Installer "$destination/unins000.exe" @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$evidence/uninstall.log`"")
if (Test-Path "$destination/busybooks.exe") { throw 'Uninstall left the application executable behind' }
if ((Test-Path $uninstallKey) -or (Test-Path $shortcut)) { throw 'Uninstall left its registration or shortcut behind' }
if (Test-Path 'HKCU:\Software\Classes\BusyBooks.Book') { throw 'Uninstall left the application ProgID behind' }
foreach ($extension in '.epub', '.pdf', '.fb2', '.fbz', '.cbz', '.cbr') {
    $key = "HKCU:\Software\Classes\$extension\OpenWithProgids"
    if ((Test-Path $key) -and (Get-ItemProperty $key).PSObject.Properties.Name -contains 'BusyBooks.Book') { throw "Uninstall left association: $extension" }
}
@{status='passed'; scope='Silent install, exact staged bytes, x64/version/assets/vendor/decoder, per-user shortcut and uninstall registration, optional associations, native-window startup and normal close, uninstall'; manualAcceptance='Required: unelevated clean Windows desktop, runtime first install, WebView2 rendering and complete GUI checks'} | ConvertTo-Json | Set-Content "$evidence/installer-results.json"
