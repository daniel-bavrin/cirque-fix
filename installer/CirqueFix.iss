; CirqueFix Inno Setup installer script
; Requires Inno Setup 6+ from https://jrsoftware.org/isinfo.php

#define AppName "CirqueFix"
#define AppVersion "1.0.0"
#define AppPublisher "CirqueFix Contributors"
#define AppURL "https://github.com/YOUR_USERNAME/CirqueFix"
#define AppExeName "CirqueFix.exe"
#define TaskName "CirqueFix"

[Setup]
AppId={8F3A2B1C-4D5E-6F7A-8B9C-0D1E2F3A4B5C}
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
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
VersionInfoVersion={#AppVersion}
VersionInfoDescription=CirqueFix - Restores TrackPoint scroll after Windows lock/unlock

; Enable repair/modify/uninstall on second run
; Inno Setup handles this automatically when AppId is set — running the installer
; again when already installed shows a maintenance dialog with these options.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\publish\self-contained\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Tasks]
Name: "schedtask"; Description: "Start automatically at logon (recommended)"; Flags: checkedonce

[Run]
; Stop any running instance before updating files
Filename: "schtasks.exe"; \
  Parameters: "/end /tn ""{#TaskName}"""; \
  Flags: runhidden waituntilterminated; \
  StatusMsg: "Stopping existing instance..."

; Register the logon task
Filename: "schtasks.exe"; \
  Parameters: "/create /tn ""{#TaskName}"" /tr """"""{app}\{#AppExeName}"" --watch"" /sc onlogon /ru ""%USERNAME%"" /f /rl limited"; \
  Flags: runhidden waituntilterminated; \
  Tasks: schedtask; \
  StatusMsg: "Registering startup task..."

; Start immediately — don't make the user log out and back in
Filename: "schtasks.exe"; \
  Parameters: "/run /tn ""{#TaskName}"""; \
  Flags: runhidden waituntilterminated; \
  Tasks: schedtask; \
  StatusMsg: "Starting CirqueFix..."

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/end /tn ""{#TaskName}"""; Flags: runhidden
Filename: "schtasks.exe"; Parameters: "/delete /tn ""{#TaskName}"" /f"; Flags: runhidden

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;

// After a repair/reinstall, restart the task even if the schedtask checkbox
// is not shown (it's only shown on first install via "checkedonce")
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssDone then
  begin
    // Always restart the task after any install/repair so the user
    // doesn't have to log out and back in
    Exec('schtasks.exe',
      '/end /tn "' + '{#TaskName}' + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('schtasks.exe',
      '/run /tn "' + '{#TaskName}' + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption :=
      'CirqueFix has been installed and is now running.' + #13#10 + #13#10 +
      'It will automatically restore TrackPoint scroll ' +
      'after every lock/unlock and sleep/wake.' + #13#10 + #13#10 +
      'To uninstall, use Add/Remove Programs.' + #13#10 +
      'Running this installer again will offer Repair and Uninstall options.';
  end;
end;
