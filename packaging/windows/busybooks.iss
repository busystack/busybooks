#define MyAppVersion "0.1.0"
[Setup]
AppId=io.busystack.busybooks
AppName=BusyBooks
AppVersion={#MyAppVersion}
AppPublisher=BusyStack
DefaultDirName={localappdata}\Programs\BusyBooks
DefaultGroupName=BusyBooks
PrivilegesRequired=lowest
OutputBaseFilename=BusyBooks-{#MyAppVersion}-windows-x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\busybooks.exe
Compression=lzma2
SolidCompression=yes
[Files]
Source: "..\..\build\distributions\windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\BusyBooks"; Filename: "{app}\busybooks.exe"
[Tasks]
Name: "epub"; Description: "Open EPUB books with BusyBooks"; Flags: unchecked
Name: "pdf"; Description: "Open PDF books with BusyBooks"; Flags: unchecked
Name: "fb2"; Description: "Open FictionBook books with BusyBooks"; Flags: unchecked
Name: "comics"; Description: "Open CBZ and CBR comics with BusyBooks"; Flags: unchecked
[Registry]
Root: HKCU; Subkey: "Software\Classes\BusyBooks.Book"; ValueType: string; ValueData: "BusyBooks book"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\BusyBooks.Book\shell\open\command"; ValueType: string; ValueData: """{app}\busybooks.exe"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\.epub\OpenWithProgids"; ValueType: string; ValueName: "BusyBooks.Book"; ValueData: ""; Tasks: epub; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "BusyBooks.Book"; ValueData: ""; Tasks: pdf; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.fb2\OpenWithProgids"; ValueType: string; ValueName: "BusyBooks.Book"; ValueData: ""; Tasks: fb2; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.fbz\OpenWithProgids"; ValueType: string; ValueName: "BusyBooks.Book"; ValueData: ""; Tasks: fb2; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.cbz\OpenWithProgids"; ValueType: string; ValueName: "BusyBooks.Book"; ValueData: ""; Tasks: comics; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.cbr\OpenWithProgids"; ValueType: string; ValueName: "BusyBooks.Book"; ValueData: ""; Tasks: comics; Flags: uninsdeletevalue
[Run]
Filename: "{app}\busybooks.exe"; Description: "Launch BusyBooks"; Flags: nowait postinstall skipifsilent

[Code]
function WebViewInstalled: Boolean;
var
  Version: String;
  Key: String;
begin
  Key := 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  Result := (RegQueryStringValue(HKLM32, Key, 'pv', Version) or
             RegQueryStringValue(HKCU, Key, 'pv', Version)) and
            (Version <> '') and (Version <> '0.0.0.0');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  Result := '';
  ExtractTemporaryFile('VC_redist.x64.exe');
  if not Exec(ExpandConstant('{tmp}\VC_redist.x64.exe'),
              '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Result := 'Could not start the Microsoft Visual C++ x64 runtime installer.'
  else if (Code <> 0) and (Code <> 3010) and (Code <> 1638) then
    Result := Format('Microsoft Visual C++ runtime installation failed (%d).', [Code]);
  { 1638 means a newer redistributable is already installed. }
  if Code = 3010 then NeedsRestart := True;
  if (Result = '') and not WebViewInstalled then begin
    ExtractTemporaryFile('MicrosoftEdgeWebView2RuntimeInstallerX64.exe');
    if not Exec(ExpandConstant('{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'),
                '/silent /install', '', SW_HIDE, ewWaitUntilTerminated, Code) then
      Result := 'Could not start the Microsoft WebView2 Evergreen x64 installer.'
    else if Code <> 0 then
      Result := Format('Microsoft WebView2 runtime installation failed (%d).', [Code]);
    if (Result = '') and not WebViewInstalled then
      Result := 'Microsoft WebView2 Runtime registration is missing after installation.';
  end;
end;
