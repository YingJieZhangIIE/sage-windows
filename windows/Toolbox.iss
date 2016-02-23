#define MyAppName "SageMath Windows"
#define MyAppPublisher "SageMath"
#define MyAppURL "http://www.sagemath.org/"
#define MyAppContact "http://www.sagemath.org/"

#define SageGroupName "SageMath"
#define sageMathImage "..\bundle\sagemath.tar"
#define b2dIsoPath "..\bundle\boot2docker.iso"
#define dockerCli "..\bundle\docker.exe"
#define dockerMachineCli "..\bundle\docker-machine.exe"
//#define dockerComposeCli "..\bundle\docker-compose.exe"
#define virtualBoxCommon "..\bundle\common.cab"
#define virtualBoxMsi "..\bundle\VirtualBox_amd64.msi"

[Setup]
AppCopyright={#MyAppPublisher}
AppId={{723D6855-C02C-42AE-92E7-8DFEDA411195}
AppContact={#MyAppContact}
AppComments={#MyAppURL}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
DefaultDirName={pf}\{#SageGroupName}
DefaultGroupName={#SageGroupName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
DiskSpanning=yes
OutputBaseFilename={#SageGroupName}
Compression=lzma
SolidCompression=yes
WizardImageFile=windows-installer-side.bmp
WizardSmallImageFile=windows-installer-logo.bmp
WizardImageStretch=yes
UninstallDisplayIcon={app}\unins000.exe
SetupIconFile=toolbox.ico
ChangesEnvironment=true
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Types]
Name: "full"; Description: "Full installation"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Run]
Filename: "{win}\explorer.exe"; Parameters: "{userprograms}\{#SageGroupName}\"; Flags: postinstall skipifsilent; Description: "View Shortcuts in File Explorer"

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"
Name: modifypath; Description: "Add docker binaries to &PATH"
Name: upgradevm; Description: "Upgrade Boot2Docker VM"

[Components]
Name: "VirtualBox"; Description: "VirtualBox"; Types: full custom; Flags: fixed disablenouninstallwarning
Name: "Docker"; Description: "Docker for Windows" ; Types: full custom; Flags: fixed
Name: "SageMath"; Description: "SageMath image for Docker"; Types: full custom; Flags: fixed

[Files]
Source: "{#dockerCli}"; DestDir: "{app}"; Flags: ignoreversion; Components: "Docker"
Source: "{#dockerMachineCli}"; DestDir: "{app}"; Flags: ignoreversion; Components: "Docker"
//Source: "{#dockerComposeCli}"; DestDir: "{app}"; Flags: ignoreversion; Components: "Docker"
Source: "{#b2dIsoPath}"; DestDir: "{app}"; Flags: ignoreversion; Components: "Docker"; AfterInstall: CopyBoot2DockerISO()
Source: "{#virtualBoxCommon}"; DestDir: "{app}\installers\virtualbox"; Components: "VirtualBox"
Source: "{#virtualBoxMsi}"; DestDir: "{app}\installers\virtualbox"; DestName: "virtualbox.msi"; AfterInstall: RunInstallVirtualBox(); Components: "VirtualBox"
Source: "{#sageMathImage}"; Components: "SageMath"; Flags: dontcopy
// NOTE: This file has more to do with Docker than sage itself.  It's the
// equivalent to start.sh which comes with Docker Toolbox, but written
// for MS powershell, so that we don't strictly need to install Git
// Eventually we could avoid shipping this if Docker Toolbox starts
// including it; see https://github.com/docker/toolbox/pull/321 
Source: ".\Start-DockerMachine.ps1"; DestDir: "{app}"; Flags: ignoreversion; Components: "SageMath"

[Code]
#include "base64.iss"
#include "guid.iss"

const
  // TODO: Maybe InnoSetup has a nicer way to do this built-in
  VirtualBoxComponent = 0;
  DockerComponent = 1;

var
  TrackingDisabled: Boolean;
//  TrackingCheckBox: TNewCheckBox;

function uuid(): String;
var
  dirpath: String;
  filepath: String;
  ansiresult: AnsiString;
begin
  dirpath := ExpandConstant('{userappdata}\DockerToolbox');
  filepath := dirpath + '\id.txt';
  ForceDirectories(dirpath);

  Result := '';
  if FileExists(filepath) then
    LoadStringFromFile(filepath, ansiresult);
    Result := String(ansiresult)

  if Length(Result) = 0 then
    Result := GetGuid('');
    StringChangeEx(Result, '{', '', True);
    StringChangeEx(Result, '}', '', True);
    SaveStringToFile(filepath, AnsiString(Result), False);
end;

function WindowsVersionString(): String;
var
  ResultCode: Integer;
  lines : TArrayOfString;
begin
  if not Exec(ExpandConstant('{cmd}'), ExpandConstant('/c wmic os get caption | more +1 > C:\windows-version.txt'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then begin
    Result := 'N/A';
    exit;
  end;

  if LoadStringsFromFile(ExpandConstant('C:\windows-version.txt'), lines) then begin
    Result := lines[0];
  end else begin
    Result := 'N/A'
  end;
end;

procedure TrackEventWithProperties(name: String; properties: String);
var
  payload: String;
  WinHttpReq: Variant;
begin
  if TrackingDisabled or WizardSilent() then
    exit;

  if Length(properties) > 0 then
    properties := ', ' + properties;

  try
//    payload := Encode64(Format(ExpandConstant('{{"event": "%s", "properties": {{"token": "{#MixpanelToken}", "distinct_id": "%s", "os": "win32", "os version": "%s", "version": "{#MyAppVersion}" %s}}'), [name, uuid(), WindowsVersionString(), properties]));
    payload := '';
    WinHttpReq := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    WinHttpReq.Open('POST', 'https://api.mixpanel.com/track/?data=' + payload, false);
    WinHttpReq.SetRequestHeader('Content-Type', 'application/json');
    WinHttpReq.Send('');
  except
  end;
end;

procedure TrackEvent(name: String);
begin
  TrackEventWithProperties(name, '');
end;

function NeedToInstallVirtualBox(): Boolean;
begin
  // TODO: Also compare versions
  Result := (
    (GetEnv('VBOX_INSTALL_PATH') = '')
    and
    (GetEnv('VBOX_MSI_INSTALL_PATH') = '')
  );
end;

function VBoxPath(): String;
begin
  if GetEnv('VBOX_INSTALL_PATH') <> '' then
    Result := GetEnv('VBOX_INSTALL_PATH')
  else
    Result := GetEnv('VBOX_MSI_INSTALL_PATH')
end;

function DockerPath(): String;
var
  Path: String;
begin
  if RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'DOCKER_TOOLBOX_INSTALL_PATH', Path) then
    Result := Path
  else
    Result := '';
end;

function NeedToInstallDocker(): Boolean;
begin
  // TODO: Should also attempt to run the docker CLI and check the
  // client and server versions (if the CLI even runs successfully)
  if DockerPath() = '' then
    Result := True
  else
    Result := False;
end;

procedure InitializeWizard;
var
  WelcomePage: TWizardPage;
  InstallDockerCaption: String;
  InstallVBoxCaption: String;
//  TrackingLabel: TLabel;
begin
  TrackingDisabled := True;  // Remove this if we re-enable tracking
  WelcomePage := PageFromID(wpWelcome)

  WizardForm.WelcomeLabel2.AutoSize := True;

//  TrackingCheckBox := TNewCheckBox.Create(WizardForm);
//  TrackingCheckBox.Top := WizardForm.WelcomeLabel2.Top + WizardForm.WelcomeLabel2.Height + 10;
//  TrackingCheckBox.Left := WizardForm.WelcomeLabel2.Left;
//  TrackingCheckBox.Width := WizardForm.WelcomeLabel2.Width;
//  TrackingCheckBox.Height := 28;
//  TrackingCheckBox.Caption := 'Help Docker improve Toolbox.';
//  TrackingCheckBox.Checked := True;
//  TrackingCheckBox.Parent := WelcomePage.Surface;

//  TrackingLabel := TLabel.Create(WizardForm);
//  TrackingLabel.Parent := WelcomePage.Surface;
//  TrackingLabel.Font := WizardForm.WelcomeLabel2.Font;
//  TrackingLabel.Font.Color := clGray;
//  TrackingLabel.Caption := 'This collects anonymous data to help us detect installation problems and improve the overall experience. We only use it to aggregate statistics and will never share it with third parties.';
//  TrackingLabel.WordWrap := True;
//  TrackingLabel.Visible := True;
//  TrackingLabel.Left := WizardForm.WelcomeLabel2.Left;
//  TrackingLabel.Width := WizardForm.WelcomeLabel2.Width;
//  TrackingLabel.Top := TrackingCheckBox.Top + TrackingCheckBox.Height + 5;
//  TrackingLabel.Height := 100;

// TODO: It seems to me the following two optional component install
// routines could be made into a general procedure

  InstallDockerCaption := Wizardform.ComponentsList.ItemCaption[DockerComponent];

  if NeedToInstallDocker() then
  begin
    Wizardform.ComponentsList.Checked[DockerComponent] := True;
  end else begin
    InstallDockerCaption := InstallDockerCaption + ' (already installed)';
    Wizardform.ComponentsList.Checked[DockerComponent] := False;
  end;

  Wizardform.ComponentsList.ItemCaption[DockerComponent] := InstallDockerCaption;

  InstallVBoxCaption := Wizardform.ComponentsList.ItemCaption[VirtualBoxComponent];
  // Don't do this until we can compare versions
  // Wizardform.ComponentsList.Checked[VirtualBoxComponent] := NeedToInstallVirtualBox();
  if NeedToInstallVirtualBox() then
  begin
    Wizardform.ComponentsList.Checked[VirtualBoxComponent] := True;
  end else begin
    InstallVBoxCaption := InstallVBoxCaption + ' (already installed)';
    Wizardform.ComponentsList.Checked[VirtualBoxComponent] := False;
  end;

  Wizardform.ComponentsList.ItemCaption[VirtualBoxComponent] := InstallVBoxCaption;
    
end;

function InitializeSetup(): boolean;
begin
  TrackEvent('Installer Started');
  Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  if CurPageID = wpWelcome then begin
      //if TrackingCheckBox.Checked then begin
      if False then begin
        TrackEventWithProperties('Continued from Overview', '"Tracking Enabled": "Yes"');
        TrackingDisabled := False;
        DeleteFile(ExpandConstant('{userdocs}\..\.docker\machine\no-error-report'));
      end else begin
        TrackEventWithProperties('Continued from Overview', '"Tracking Enabled": "No"');
        TrackingDisabled := True;
        CreateDir(ExpandConstant('{userdocs}\..\.docker\machine'));
        SaveStringToFile(ExpandConstant('{userdocs}\..\.docker\machine\no-error-report'), '', False);
      end;
  end;
  Result := True
end;

procedure RunInstallVirtualBox();
var
  ResultCode: Integer;
begin
  WizardForm.FilenameLabel.Caption := 'installing VirtualBox'
  if not Exec(ExpandConstant('msiexec'), ExpandConstant('/qn /i "{app}\installers\virtualbox\virtualbox.msi" /norestart'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    MsgBox('virtualbox install failure', mbInformation, MB_OK);
end;

procedure CopyBoot2DockerISO();
begin
  WizardForm.FilenameLabel.Caption := 'copying boot2docker iso'
  if not ForceDirectories(ExpandConstant('{userdocs}\..\.docker\machine\cache')) then
      MsgBox('Failed to create docker machine cache dir', mbError, MB_OK);
  if not FileCopy(ExpandConstant('{app}\boot2docker.iso'), ExpandConstant('{userdocs}\..\.docker\machine\cache\boot2docker.iso'), false) then
      MsgBox('File moving failed!', mbError, MB_OK);
end;

function CanUpgradeVM(): Boolean;
var
  ResultCode: Integer;
begin
  if NeedToInstallVirtualBox() or not FileExists(ExpandConstant('{app}\docker-machine.exe')) then begin
    Result := false
    exit
  end;

  ExecAsOriginalUser(VBoxPath() + 'VBoxManage.exe', 'showvminfo default', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  if ResultCode <> 0 then begin
    Result := false
    exit
  end;

  if not DirExists(ExpandConstant('{userdocs}\..\.docker\machine\machines\default')) then begin
    Result := false
    exit
  end;

  Result := true
end;

function UpgradeVM() : Boolean;
var
  ResultCode: Integer;
begin
  TrackEvent('VM Upgrade Started');
  WizardForm.StatusLabel.Caption := 'Upgrading Docker Toolbox VM...'
  ExecAsOriginalUser(ExpandConstant('{app}\docker-machine.exe'), 'stop default', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  if (ResultCode = 0) or (ResultCode = 1) then
  begin
    FileCopy(ExpandConstant('{userdocs}\..\.docker\machine\cache\boot2docker.iso'), ExpandConstant('{userdocs}\..\.docker\machine\machines\default\boot2docker.iso'), false)
    TrackEvent('VM Upgrade Succeeded');
  end else begin
    TrackEvent('VM Upgrade Failed');
    MsgBox('VM Upgrade Failed because the VirtualBox VM could not be stopped.', mbCriticalError, MB_OK);
    Result := false
    WizardForm.Close;
    exit;
  end;
  Result := true
end;

const
  ModPathName = 'modifypath';
  ModPathType = 'user';

function ModPathDir(): TArrayOfString;
begin
  setArrayLength(Result, 1);
  Result[0] := ExpandConstant('{app}');
end;
#include "modpath.iss"

// This step starts the boot2docker VM with docker-machine
// so that we can then issue commands to the docker-engine through
// the docker client (namely load the sagemath image, which we then delete
// from the installation)
procedure RunInstallSageImage();
var
  ResultCode: Integer;
  StatusFile: String;
  MachineStatus: AnsiString;
  StartMachine: Boolean;
  CmdArgs: String;
begin
  TrackEvent('Installing the Sage image');
  // TODO Maybe worth specifying a constant for this
  WizardForm.StatusLabel.Caption := 'Extracting Sage image archive...';
  ExtractTemporaryFile('sagemath.tar');

  WizardForm.StatusLabel.Caption := 'Checking Docker VM status...';
  // This is unfortunate...
  StatusFile := ExpandConstant('{tmp}\docker-machine-status.txt');
  CmdArgs := Format('/S /C ""%s\docker-machine.exe" status default > "%s""', [DockerPath(), StatusFile]);
  Log(Format(ExpandConstant('Running {cmd} %s'), [CmdArgs]));
  ExecAsOriginalUser(ExpandConstant('{cmd}'), CmdArgs, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  WizardForm.StatusLabel.Caption := 'Checking Docker VM status... [OK]';
  if (ResultCode = 0) then
  begin
    LoadStringFromFile(StatusFile, MachineStatus);
    StartMachine := 0 <> CompareText('running', TrimRight(String(MachineStatus)));
  end else begin
    StartMachine := True
  end;

  if StartMachine then
  begin
    // TODO This could take a few minutes and appear to hang.  Figure out some way
    // to update a progress bar, or at least display a spinner?
    WizardForm.StatusLabel.Caption := 'Starting Docker VM...'
    ExecAsOriginalUser(DockerPath() + '\docker-machine.exe', 'start default', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if (ResultCode = 0) then
    begin
      WizardForm.StatusLabel.Caption := 'Starting Docker VM... [OK]';
    end else begin
      // TODO: Update these messages
      TrackEvent('VM Upgrade Failed');
      MsgBox('VM Upgrade Failed because the Docker VM could not be started', mbCriticalError, MB_OK);
      WizardForm.Close;
      exit;
    end;
  end;

  // TODO: This is also quite time consuming--try to provide a
  // progress bar if possible...?
  WizardForm.StatusLabel.Caption := 'Loading SageMath image into Docker...';
  ExecAsOriginalUser(DockerPath() + '\docker.exe',
                     ExpandConstant('load -i "{tmp}\sagemath.tar"'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  WizardForm.StatusLabel.Caption := 'Loading SageMath image into Docker... [OK]';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Success: Boolean;
begin
  Success := True;
  if CurStep = ssPostInstall then
  begin
    trackEvent('Installing Files Succeeded');
    if IsTaskSelected(ModPathName) then
      ModPath();
    if not WizardSilent() then
    begin
      if IsTaskSelected('upgradevm') then
      begin
        if CanUpgradeVM() then begin
          Success := UpgradeVM();
        end;
      end;
    end;

    RunInstallSageImage();

    if Success then
      trackEvent('Installer Finished');
  end;
end;
