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
[Registry]
Root: HKCU; Subkey: "Software\Classes\BusyBooks.Book"; ValueType: string; ValueData: "BusyBooks book"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\BusyBooks.Book\shell\open\command"; ValueType: string; ValueData: """{app}\busybooks.exe"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\.epub\OpenWithProgids"; ValueType: string; ValueName: "BusyBooks.Book"; ValueData: ""; Tasks: epub; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "BusyBooks.Book"; ValueData: ""; Tasks: pdf; Flags: uninsdeletevalue
[Run]
Filename: "{app}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime"; Flags: waituntilterminated
Filename: "{app}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; StatusMsg: "Installing WebView2 Runtime"; Flags: waituntilterminated
Filename: "{app}\busybooks.exe"; Description: "Launch BusyBooks"; Flags: nowait postinstall skipifsilent
