; CirqueFix Inno Setup installer script
; Requires Inno Setup 6+ from https://jrsoftware.org/isinfo.php

#define AppName "CirqueFix"
#ifndef AppVersion
  #define AppVersion "0.0.0-local"
#endif
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
DefaultDirName={autopf64}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\publish\installer
OutputBaseFilename=CirqueFix-{#AppVersion}-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
; Force 64-bit mode — prevents installing to Program Files (x86)
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
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

[Run]
; Nothing here — task registration is handled in CurStepChanged below
; to ensure correct path expansion and visible error on failure

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/end /tn ""{#TaskName}"""; Flags: runhidden
Filename: "schtasks.exe"; Parameters: "/delete /tn ""{#TaskName}"" /f"; Flags: runhidden

[Code]
function InitializeSetup(): Boolean;
var
  UninstallKey: String;
  UninstallExe: String;
  ResultCode: Integer;
begin
  Result := True;
  // Clean up any previous install that used a different AppId
  // (can happen after failed/partial installs)
  UninstallKey := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\CirqueFix_is1';
  if RegQueryStringValue(HKLM, UninstallKey, 'UninstallString', UninstallExe) then
  begin
    // Only clean up if it's a different AppId than ours
    if Pos('{8F3A2B1C-4D5E-6F7A-8B9C-0D1E2F3A4B5C}', UninstallExe) = 0 then
    begin
      if MsgBox('A previous version of CirqueFix is installed. Remove it before continuing?',
        mbConfirmation, MB_YESNO) = IDYES then
        Exec(UninstallExe, '/SILENT', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ExePath: String;
  TaskArgs: String;
begin
  if CurStep = ssDone then
  begin
    ExePath := ExpandConstant('{app}\{#AppExeName}');

    // Stop any existing instance
    Exec('schtasks.exe', '/end /tn "{#TaskName}"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Register logon task with fully expanded path
    TaskArgs := '/create /tn "{#TaskName}"'
      + ' /tr "\"' + ExePath + '\" --watch"'
      + ' /sc onlogon'
      + ' /ru "' + GetUserNameString + '"'
      + ' /f /rl limited';

    if not Exec('schtasks.exe', TaskArgs,
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      MsgBox('Warning: Failed to register startup task (error ' + IntToStr(ResultCode) + ').'
        + #13#10 + 'CirqueFix is installed but will not start automatically at logon.'
        + #13#10 + 'You can start it manually: ' + ExePath + ' --watch',
        mbError, MB_OK);
      Exit;
    end;

    // Start immediately — no need to log out and back in
    Exec('schtasks.exe', '/run /tn "{#TaskName}"',
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
