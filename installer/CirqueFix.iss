; CirqueFix Inno Setup installer script
; Requires Inno Setup 6+ from https://jrsoftware.org/isinfo.php

#define AppName "CirqueFix"
#ifndef AppVersion
  #define AppVersion "0.0.0.0"
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
OutputDir=..\publish\installer
OutputBaseFilename=CirqueFix-{#AppVersion}-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
; Force 64-bit mode — prevents installing to Program Files (x86)
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; On upgrade, don't ask user to confirm install dir or start menu group
DisableDirPage=auto
DisableProgramGroupPage=auto
; Close CirqueFix.exe automatically without prompting — force closes it
CloseApplications=force
; Don't create a Start Menu group — the app runs silently in the background
CreateUninstallRegKey=yes
; Skip the "Ready to Install" confirmation page — reduces unnecessary clicks
DisableReadyPage=yes
DirExistsWarning=no
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
VersionInfoVersion={#AppVersion}
VersionInfoDescription=CirqueFix - Restores TrackPoint scroll after Windows lock/unlock

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\publish\self-contained\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Run]
; Register the logon task with auto-restart on failure — uses PowerShell for full task settings
Filename: "powershell.exe"; \
  Parameters: "-NonInteractive -WindowStyle Hidden -Command ""$a = New-ScheduledTaskAction -Execute '{code:GetExePath}' -Argument '--watch'; $t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME; $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable; Register-ScheduledTask -TaskName 'CirqueFix' -Action $a -Trigger $t -Settings $s -RunLevel Limited -Force"""; \
  Flags: runhidden waituntilterminated; \
  StatusMsg: "Registering startup task..."
; Launch app — nowait so installer doesn't block on the background process.
; The 2s delay in CurStepChanged(ssDone) ensures it initializes before Finish page.
Filename: "{app}\{#AppExeName}"; Parameters: "--watch"; \
  Flags: nowait runhidden; \
  StatusMsg: "Starting CirqueFix..."

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/end /tn ""{#TaskName}"""; Flags: runhidden
Filename: "schtasks.exe"; Parameters: "/delete /tn ""{#TaskName}"" /f"; Flags: runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
// Inno Setup has no native repair/uninstall maintenance dialog (unlike MSI).
// This implements it manually using InitializeSetup().
function InitializeSetup(): Boolean;
var
  RegKey: String;
  UninstallExe: String;
  ResultCode: Integer;
  Answer: Integer;
begin
  Result := True;
  RegKey := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' +
    '{8F3A2B1C-4D5E-6F7A-8B9C-0D1E2F3A4B5C}_is1';

  // Kill any running CirqueFix instance before Inno Setup checks for open files.
  // Without this, CloseApplications=force falls back to prompting because
  // background processes started via schtasks don't register with Restart Manager.
  Exec('schtasks.exe', '/end /tn "{#TaskName}"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/f /im "{#AppExeName}"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Small wait for the process to fully exit before file copy begins
  Sleep(500);

  if not RegQueryStringValue(HKLM, RegKey, 'UninstallString', UninstallExe) then
    Exit; // not installed — proceed normally

  Answer := MsgBox(
    'CirqueFix is already installed.' + #13#10 + #13#10 +
    'Click Yes to repair (reinstall and restart).' + #13#10 +
    'Click No to uninstall.' + #13#10 +
    'Click Cancel to exit.',
    mbConfirmation, MB_YESNOCANCEL);

  if Answer = IDCANCEL then
    Result := False
  else if Answer = IDNO then
  begin
    Exec(RemoveQuotes(UninstallExe), '/SILENT', '',
      SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Result := False; // exit after uninstall
  end;
  // IDYES: fall through and continue with reinstall
end;

function GetExePath(Param: String): String;
begin
  Result := ExpandConstant('{app}\{#AppExeName}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    // Stop any running instance before file copy
    Exec('taskkill.exe', '/f /im "{#AppExeName}"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  if CurStep = ssDone then
  begin
    // Wait for the app to initialize after [Run] launched it
    Sleep(2000);
  end;
end;
