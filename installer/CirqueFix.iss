; CirqueFix Inno Setup installer script
; Requires Inno Setup 6+ from https://jrsoftware.org/isinfo.php

#define AppName "CirqueFix"
#define AppVersion "1.0.0"
#define AppPublisher "CirqueFix Contributors"
#define AppURL "https://github.com/YOUR_USERNAME/CirqueFix"
#define AppExeName "CirqueFix.exe"
#define TaskName "CirqueFix"

[Setup]
AppId={{8F3A2B1C-4D5E-6F7A-8B9C-0D1E2F3A4B5C}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\publish\installer
OutputBaseFilename=CirqueFix-{#AppVersion}-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; No elevation needed for the app itself, but we need it to install to ProgramFiles
PrivilegesRequired=admin
; Show "Launch CirqueFix" checkbox at end
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
VersionInfoVersion={#AppVersion}
VersionInfoDescription=CirqueFix — Restores TrackPoint scroll after Windows lock/unlock

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; The built exe — Inno Setup will embed it in the installer
Source: "..\publish\self-contained\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Start Menu shortcut (optional, most users won't need it since it runs in background)
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Parameters: "--watch"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Tasks]
; Offered as a checkbox during install — checked by default
Name: "schedtask"; Description: "Start automatically at logon (recommended)"; Flags: checkedonce

[Run]
; Register the Task Scheduler entry if the user checked the box
Filename: "schtasks.exe"; \
  Parameters: "/create /tn ""{#TaskName}"" /tr """"""{app}\{#AppExeName}"" --watch"" /sc onlogon /ru ""%USERNAME%"" /f /rl limited"; \
  Flags: runhidden waituntilterminated; \
  Tasks: schedtask; \
  StatusMsg: "Registering startup task..."

; Start it immediately after install (don't make user reboot)
Filename: "schtasks.exe"; \
  Parameters: "/run /tn ""{#TaskName}"""; \
  Flags: runhidden waituntilterminated; \
  Tasks: schedtask; \
  StatusMsg: "Starting CirqueFix..."

[UninstallRun]
; Stop and remove the scheduled task on uninstall
Filename: "schtasks.exe"; Parameters: "/end /tn ""{#TaskName}"""; Flags: runhidden
Filename: "schtasks.exe"; Parameters: "/delete /tn ""{#TaskName}"" /f"; Flags: runhidden

[Code]
// Show a friendly finish message
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption :=
      'CirqueFix has been installed.' + #13#10 + #13#10 +
      'It will now automatically restore TrackPoint scroll ' +
      'after every lock/unlock and sleep/wake.' + #13#10 + #13#10 +
      'You can uninstall it at any time from Add/Remove Programs.';
  end;
end;
