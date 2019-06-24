program CitrixFilesAdminMapper;
{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

//{$APPTYPE CONSOLE}
{$R *.res}

{$R 'uac.res' 'uac.rc'}

uses
  Windows,
  Registry,
  System.IOUtils,
  System.SysUtils;
//  MainUnit in 'MainUnit.pas';

{$IFDEF RELEASE}
const
  IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE = $0040;
  IMAGE_DLLCHARACTERISTICS_NX_COMPAT    = $0100;

{$DYNAMICBASE ON} // prereq for ASLR / NX

{$SETPEFLAGS IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE or
  IMAGE_DLLCHARACTERISTICS_NX_COMPAT or IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE or
  IMAGE_FILE_DEBUG_STRIPPED or IMAGE_FILE_LINE_NUMS_STRIPPED or
  IMAGE_FILE_LOCAL_SYMS_STRIPPED}
{$ENDIF}

type
  NTSTATUS = Cardinal;
  TfnFspFsctlGetVolumeList = function(DeviceName: PChar; PVolumeListBuf:PChar; var PVolumeListSize: SIZE_T): NTSTATUS; stdcall;

const
  FSP_FSCTL_DISK_DEVICE_NAME: PChar = 'CitrixFSP.Disk';
  STATUS_SUCCESS: NTSTATUS = 0;

function GetCFRootLocation: String;
var
  Reg: TRegistry;
begin
  Result := 'S:'; // default

  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Citrix\Citrix Files\RootFolders') then
    begin
      Result := Reg.ReadString('RootLocation');
    end;
  finally
    Reg.Free;
  end;
end;

function GetWinFspFolder: String;
var
  Reg: TRegistry;
begin
  Result := 'C:\Program Files\Citrix\Citrix Files\CitrixFsp\bin'; // default

  Reg := TRegistry.Create(KEY_WOW64_64KEY or KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('SOFTWARE\Citrix\Citrix Files\CitrixFsp') then
    begin
      Result := TPath.Combine(Reg.ReadString('InstallDir'), 'bin');
    end;
  finally
    Reg.Free;
  end;
end;

function GetSFVolumeName: String;
var
  hModule: THandle;
  FspFsctlGetVolumeList: TfnFspFsctlGetVolumeList;
  nts: NTSTATUS;
  VolumeListBuf: PChar;
  VolumeListSize: SIZE_T;
  DllFolder: String;
  DllPath:String;
begin
  Result := '';
  DllFolder := GetWinFspFolder;
  DllPath := TPath.Combine(DllFolder, 'citrixfsp-x86.dll');

  hModule := LoadLibrary(PChar(DllPath));
  if hModule = 0 then
    RaiseLastOSError;

  FspFsctlGetVolumeList := GetProcAddress(hModule, 'FspFsctlGetVolumeList');
  if not Assigned(FspFsctlGetVolumeList) then
    RaiseLastOSError;


  GetMem(VolumeListBuf, VolumeListSize);
  try
    repeat
      VolumeListSize := 2048;
      nts := FspFsctlGetVolumeList(FSP_FSCTL_DISK_DEVICE_NAME, VolumeListBuf, VolumeListSize);
      if nts <> STATUS_SUCCESS then
        Exit;

      if VolumeListSize > 0 then
      begin
        Result := String(VolumeListBuf);
        Break;
      end;

      OutputDebugString('retrying...');
      Sleep(500);
    until False;

  finally
    FreeMem(VolumeListBuf);
  end;

end;


var
  bRes: Boolean;
  RootLocation: String;
  SFVolumeName: String;
begin
  SFVolumeName := GetSFVolumeName;
  RootLocation := GetCFRootLocation;
  bRes := DefineDosDevice(DDD_RAW_TARGET_PATH, PChar(RootLocation), PChar(SFVolumeName));

  if not bRes then
    RaiseLastOSError;
end.
