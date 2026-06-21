; ============================================================
; ENLIP POs — Inno Setup Script
; Empaca: Frontend Electron (win-unpacked) + Backend .NET 8
; ============================================================

#define AppName      "KAIRO POs"
#ifndef AppVersion
  #define AppVersion   "1.0.0"
#endif
#ifndef AppChannel
  #define AppChannel   "stable"
#endif
#define AppPublisher "KAIRO"
#define AppId        "{{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}"
#define AppExeName   "KAIRO POs.exe"
#ifndef UpdateServerUrl
  #define UpdateServerUrl "https://raw.githubusercontent.com/esbanegas/kairo-desktop/main/installer/updates"
#endif

#define FrontendDir  "..\..\acg-web\release\win-unpacked"
#define BackendDir   "..\..\enlip-services\ENLIPWebApi\bin\Release\net8.0\publish"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename=ENLIP_Setup_v{#AppVersion}
OutputDir=output
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0
PrivilegesRequired=admin
SetupIconFile=assets\enlip.ico
UninstallDisplayIcon={app}\{#AppExeName}
DisableProgramGroupPage=yes

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el Escritorio"; GroupDescription: "Iconos adicionales:"; Flags: unchecked

[Files]
; ── Application files ──────────────────────────────────────────────────
Source: "{#FrontendDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb"
Source: "{#BackendDir}\*"; DestDir: "{app}\api"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb,appsettings*.json,appsettings - Copy*.json,web.config"
; appsettings.json: onlyifdoesntexist preserves DB credentials on reinstall.
; WriteAppSettings procedure handles the FIRST install write.
Source: "{#BackendDir}\appsettings.json"; DestDir: "{app}\api"; Flags: ignoreversion onlyifdoesntexist

; ── Version manifest (read by backend and Electron) ────────────────────
Source: "version.json"; DestDir: "{app}"; Flags: ignoreversion

; ── Kairo Updater (external process that replaces files after Electron exits)
Source: "assets\kairo-updater\kairo-updater.exe"; DestDir: "{app}\updater"; Flags: ignoreversion; Check: UpdaterExists

; ── Dependencies ────────────────────────────────────────────────────────
Source: "assets\postgresql_installer.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\postgresql_installer.exe"; Parameters: "{code:GetPostgresInstallerParams}"; StatusMsg: "Instalando PostgreSQL..."; Check: ShouldInstallPostgres
Filename: "{app}\{#AppExeName}"; Description: "Abrir {#AppName} ahora"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]

var
  PgModePage: TWizardPage;
  AutoModeRadio: TRadioButton;
  CustomModeRadio: TRadioButton;
  AutoModeLabel: TLabel;
  CustomModeLabel: TLabel;

  PgConfigPage: TWizardPage;
  PgHost: TEdit;
  PgPort: TEdit;
  PgAdminUser: TEdit;
  PgAdminPass: TEdit;
  PgDbName: TEdit;
  PgAppUser: TEdit;
  PgAppPass: TEdit;

  PgHostLabel: TLabel;
  PgPortLabel: TLabel;
  PgAdminUserLabel: TLabel;
  PgAdminPassLabel: TLabel;
  PgDbNameLabel: TLabel;
  PgAppUserLabel: TLabel;
  PgAppPassLabel: TLabel;

  { ── Update Server page ── }
  UpdatePage: TWizardPage;
  UpdateServerEdit: TEdit;
  UpdateServerLabel: TLabel;
  UpdateServerNote: TLabel;

function ShouldInstallPostgres: Boolean;
var
  PostgresKey: String;
  InstalledVersion: String;
begin
  Result := True;
  PostgresKey := 'SOFTWARE\PostgreSQL Global Development Group\PostgreSQL';
  if RegQueryStringValue(HKLM64, PostgresKey, 'Version', InstalledVersion) or
     RegQueryStringValue(HKLM32, PostgresKey, 'Version', InstalledVersion) then
  begin
    Result := False;
    Log('PostgreSQL encontrado: v' + InstalledVersion + ' omitiendo instalacion.');
  end
  else
    Log('PostgreSQL no encontrado, se instalara.');
end;

function UpdaterExists: Boolean;
begin
  Result := FileExists(ExpandConstant('{src}\assets\kairo-updater\kairo-updater.exe'));
  if not Result then
    Log('kairo-updater.exe no encontrado en assets - se omitira en esta version.');
end;

function GetPostgresInstallerParams(Value: String): String;
var
  AdminPass: String;
begin
  if AutoModeRadio.Checked then
    AdminPass := 'postgres'
  else
    AdminPass := PgAdminPass.Text;

  Result := '--mode unattended --unattendedmodeui minimal --disable-components stackbuilder --postgrespassword "' + AdminPass + '"';
end;

function WinGetTickCount: DWord; external 'GetTickCount@kernel32.dll stdcall';

var
  RandSeed: LongInt;

procedure InitRand;
begin
  RandSeed := WinGetTickCount;
end;

function GetRand(Max: Integer): Integer;
begin
  RandSeed := (RandSeed * 1103515245 + 12345) and $7FFFFFFF;
  Result := RandSeed mod Max;
end;

function GenerateRandomPassword(PassLength: Integer): string;
var
  Chars: string;
  I: Integer;
  Idx: Integer;
begin
  Chars := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  Result := '';
  for I := 1 to PassLength do
  begin
    Idx := GetRand(Length(Chars)) + 1;
    Result := Result + Copy(Chars, Idx, 1);
  end;
end;

procedure CreatePgModePage;
begin
  PgModePage := CreateCustomPage(wpSelectDir, 'Modo de Configuración de Base de Datos',
    'Elige cómo deseas configurar la base de datos PostgreSQL.');

  AutoModeRadio := TRadioButton.Create(PgModePage);
  AutoModeRadio.Caption := 'Modo automático (recomendado)';
  AutoModeRadio.Font.Style := [fsBold];
  AutoModeRadio.Top := 20;
  AutoModeRadio.Left := 10;
  AutoModeRadio.Width := 400;
  AutoModeRadio.Checked := True;
  AutoModeRadio.Parent := PgModePage.Surface;

  AutoModeLabel := TLabel.Create(PgModePage);
  AutoModeLabel.Caption := 'Configura PostgreSQL con valores seguros automáticos.' + #13#10 +
    'Se creará la base de datos "KAIRO_DB" y el usuario "kairo_user"' + #13#10 +
    'con una contraseña segura generada automáticamente.';
  AutoModeLabel.Top := 40;
  AutoModeLabel.Left := 30;
  AutoModeLabel.Width := 400;
  AutoModeLabel.Height := 50;
  AutoModeLabel.Parent := PgModePage.Surface;

  CustomModeRadio := TRadioButton.Create(PgModePage);
  CustomModeRadio.Caption := 'Modo personalizado (avanzado)';
  CustomModeRadio.Font.Style := [fsBold];
  CustomModeRadio.Top := 100;
  CustomModeRadio.Left := 10;
  CustomModeRadio.Width := 400;
  CustomModeRadio.Parent := PgModePage.Surface;

  CustomModeLabel := TLabel.Create(PgModePage);
  CustomModeLabel.Caption := 'Permite especificar manualmente las credenciales del' + #13#10 +
    'administrador (postgres) y los detalles de la base de datos' + #13#10 +
    'y el usuario que utilizará la aplicación.';
  CustomModeLabel.Top := 120;
  CustomModeLabel.Left := 30;
  CustomModeLabel.Width := 400;
  CustomModeLabel.Height := 50;
  CustomModeLabel.Parent := PgModePage.Surface;
end;

procedure CreatePgConfigPage;
begin
  PgConfigPage := CreateCustomPage(PgModePage.ID, 'Configuración Personalizada de PostgreSQL',
    'Ingresa las credenciales de administrador y de la aplicación.');

  // --- Fila 1: Host y Puerto ---
  PgHostLabel := TLabel.Create(PgConfigPage);
  PgHostLabel.Caption := 'Host:';
  PgHostLabel.Top := 10;
  PgHostLabel.Left := 0;
  PgHostLabel.Parent := PgConfigPage.Surface;
  
  PgHost := TEdit.Create(PgConfigPage);
  PgHost.Text := 'localhost';
  PgHost.Top := 28;
  PgHost.Left := 0;
  PgHost.Width := 180;
  PgHost.Parent := PgConfigPage.Surface;

  PgPortLabel := TLabel.Create(PgConfigPage);
  PgPortLabel.Caption := 'Puerto:';
  PgPortLabel.Top := 10;
  PgPortLabel.Left := 200;
  PgPortLabel.Parent := PgConfigPage.Surface;
  
  PgPort := TEdit.Create(PgConfigPage);
  PgPort.Text := '5432';
  PgPort.Top := 28;
  PgPort.Left := 200;
  PgPort.Width := 80;
  PgPort.Parent := PgConfigPage.Surface;

  // --- Fila 2: Administrador PostgreSQL ---
  PgAdminUserLabel := TLabel.Create(PgConfigPage);
  PgAdminUserLabel.Caption := 'Admin PostgreSQL (Usuario):';
  PgAdminUserLabel.Top := 65;
  PgAdminUserLabel.Left := 0;
  PgAdminUserLabel.Parent := PgConfigPage.Surface;
  
  PgAdminUser := TEdit.Create(PgConfigPage);
  PgAdminUser.Text := 'postgres';
  PgAdminUser.Top := 83;
  PgAdminUser.Left := 0;
  PgAdminUser.Width := 180;
  PgAdminUser.Parent := PgConfigPage.Surface;

  PgAdminPassLabel := TLabel.Create(PgConfigPage);
  PgAdminPassLabel.Caption := 'Admin PostgreSQL (Contraseña):';
  PgAdminPassLabel.Top := 65;
  PgAdminPassLabel.Left := 200;
  PgAdminPassLabel.Parent := PgConfigPage.Surface;
  
  PgAdminPass := TEdit.Create(PgConfigPage);
  PgAdminPass.PasswordChar := '*';
  PgAdminPass.Text := '';
  PgAdminPass.Top := 83;
  PgAdminPass.Left := 200;
  PgAdminPass.Width := 180;
  PgAdminPass.Parent := PgConfigPage.Surface;

  // --- Fila 3: Base de Datos de Aplicación ---
  PgDbNameLabel := TLabel.Create(PgConfigPage);
  PgDbNameLabel.Caption := 'Nombre de Base de Datos:';
  PgDbNameLabel.Top := 120;
  PgDbNameLabel.Left := 0;
  PgDbNameLabel.Parent := PgConfigPage.Surface;
  
  PgDbName := TEdit.Create(PgConfigPage);
  PgDbName.Text := 'KAIRO_DB';
  PgDbName.Top := 138;
  PgDbName.Left := 0;
  PgDbName.Width := 180;
  PgDbName.Parent := PgConfigPage.Surface;

  // --- Fila 4: Credenciales de Aplicación ---
  PgAppUserLabel := TLabel.Create(PgConfigPage);
  PgAppUserLabel.Caption := 'Usuario de la Aplicación:';
  PgAppUserLabel.Top := 175;
  PgAppUserLabel.Left := 0;
  PgAppUserLabel.Parent := PgConfigPage.Surface;
  
  PgAppUser := TEdit.Create(PgConfigPage);
  PgAppUser.Text := 'kairo_user';
  PgAppUser.Top := 193;
  PgAppUser.Left := 0;
  PgAppUser.Width := 180;
  PgAppUser.Parent := PgConfigPage.Surface;

  PgAppPassLabel := TLabel.Create(PgConfigPage);
  PgAppPassLabel.Caption := 'Contraseña de la Aplicación:';
  PgAppPassLabel.Top := 175;
  PgAppPassLabel.Left := 200;
  PgAppPassLabel.Parent := PgConfigPage.Surface;
  
  PgAppPass := TEdit.Create(PgConfigPage);
  PgAppPass.PasswordChar := '*';
  PgAppPass.Text := '';
  PgAppPass.Top := 193;
  PgAppPass.Left := 200;
  PgAppPass.Width := 180;
  PgAppPass.Parent := PgConfigPage.Surface;
end;

procedure CreateUpdateServerPage;
begin
  UpdatePage := CreateCustomPage(PgConfigPage.ID,
    'Servidor de Actualizaciones',
    'URL desde donde la aplicacion descargara las actualizaciones automaticamente.');

  UpdateServerLabel := TLabel.Create(UpdatePage);
  UpdateServerLabel.Caption := 'URL del servidor de actualizaciones:';
  UpdateServerLabel.Top := 20;
  UpdateServerLabel.Left := 0;
  UpdateServerLabel.Parent := UpdatePage.Surface;

  UpdateServerEdit := TEdit.Create(UpdatePage);
  UpdateServerEdit.Text := '{#UpdateServerUrl}';
  UpdateServerEdit.Top := 38;
  UpdateServerEdit.Width := 420;
  UpdateServerEdit.Left := 0;
  UpdateServerEdit.Parent := UpdatePage.Surface;

  UpdateServerNote := TLabel.Create(UpdatePage);
  UpdateServerNote.Caption :=
    'Ejemplos validos:' + #13#10 +
    '  https://midominio.com/kairo-updates' + #13#10 +
    '  https://miblob.blob.core.windows.net/contenedor' + #13#10 +
    '  https://raw.githubusercontent.com/org/repo/main/releases' + #13#10 +
    '' + #13#10 +
    'Puede cambiarse despues editando version.json en la carpeta de instalacion.';
  UpdateServerNote.Top := 70;
  UpdateServerNote.Left := 0;
  UpdateServerNote.Width := 420;
  UpdateServerNote.AutoSize := False;
  UpdateServerNote.Height := 100;
  UpdateServerNote.Parent := UpdatePage.Surface;
end;

procedure InitializeWizard;
begin
  InitRand;
  CreatePgModePage;
  CreatePgConfigPage;
  CreateUpdateServerPage;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = PgConfigPage.ID then
  begin
    Result := AutoModeRadio.Checked;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = PgConfigPage.ID then
  begin
    if Trim(PgHost.Text) = '' then
    begin
      MsgBox('Por favor ingresa el host de PostgreSQL.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(PgPort.Text) = '' then
    begin
      MsgBox('Por favor ingresa el puerto de PostgreSQL.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(PgAdminUser.Text) = '' then
    begin
      MsgBox('Por favor ingresa el usuario administrador de PostgreSQL.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(PgAdminPass.Text) = '' then
    begin
      MsgBox('Por favor ingresa la contraseña del administrador de PostgreSQL.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(PgDbName.Text) = '' then
    begin
      MsgBox('Por favor ingresa el nombre de la base de datos.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(PgAppUser.Text) = '' then
    begin
      MsgBox('Por favor ingresa el usuario de la aplicación.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(PgAppPass.Text) = '' then
    begin
      MsgBox('Por favor ingresa la contraseña del usuario de la aplicación.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure WriteVersionJson;
var
  VersionPath: String;
  VersionContent: String;
  UpdateUrl: String;
begin
  VersionPath := ExpandConstant('{app}\version.json');
  UpdateUrl := Trim(UpdateServerEdit.Text);
  if UpdateUrl = '' then
    UpdateUrl := '{#UpdateServerUrl}';

  VersionContent :=
    '{' + #13#10 +
    '  "version": "' + '{#AppVersion}' + '",' + #13#10 +
    '  "channel": "' + '{#AppChannel}' + '",' + #13#10 +
    '  "update_server": "' + UpdateUrl + '"' + #13#10 +
    '}';

  SaveStringToFile(VersionPath, VersionContent, False);
  Log('version.json escrito con update_server: ' + UpdateUrl + ' y canal: ' + '{#AppChannel}');
end;

procedure WriteAppSettings;
var
  SettingsPath: String;
  Host, Port, DbName, AppUser, AppPass, AdminUser, AdminPass: String;
  ConnString: String;
  StoragePath: String;
  JsonContent: String;
begin
  SettingsPath := ExpandConstant('{app}\api\appsettings.json');
  StoragePath := ExpandConstant('{commonappdata}\KairoPOS\Files');
  StringChange(StoragePath, '\', '\\');

  if AutoModeRadio.Checked then
  begin
    Host := 'localhost';
    Port := '5432';
    DbName := 'KAIRO_DB';
    AppUser := 'kairo_user';
    AppPass := GenerateRandomPassword(16);
    AdminUser := 'postgres';
    AdminPass := 'postgres';
  end
  else
  begin
    Host := PgHost.Text;
    Port := PgPort.Text;
    DbName := PgDbName.Text;
    AppUser := PgAppUser.Text;
    AppPass := PgAppPass.Text;
    AdminUser := PgAdminUser.Text;
    AdminPass := PgAdminPass.Text;
  end;

  ConnString := 'Host=' + Host + ';Port=' + Port
    + ';Database=' + DbName + ';Username=' + AppUser
    + ';Password=' + AppPass;

  JsonContent :=
    '{' + #13#10 +
    '  "ConnectionStrings": {' + #13#10 +
    '    "ENLIP_Database": "' + ConnString + '"' + #13#10 +
    '  },' + #13#10 +
    '  "PostgresAdminSettings": {' + #13#10 +
    '    "Host": "' + Host + '",' + #13#10 +
    '    "Port": "' + Port + '",' + #13#10 +
    '    "Username": "' + AdminUser + '",' + #13#10 +
    '    "Password": "' + AdminPass + '"' + #13#10 +
    '  },' + #13#10 +
    '  "DatabaseSettings": {' + #13#10 +
    '    "TimeZone": "America/Tegucigalpa"' + #13#10 +
    '  },' + #13#10 +
    '  "Logging": {' + #13#10 +
    '    "LogLevel": {' + #13#10 +
    '      "Default": "Information",' + #13#10 +
    '      "Microsoft.AspNetCore": "Warning"' + #13#10 +
    '    }' + #13#10 +
    '  },' + #13#10 +
    '  "Storage": {' + #13#10 +
    '    "Provider": "Local",' + #13#10 +
    '    "LocalRootPath": "' + StoragePath + '",' + #13#10 +
    '    "LocalApiBaseUrl": "http://localhost:8855"' + #13#10 +
    '  },' + #13#10 +
    '  "Localization": {' + #13#10 +
    '    "SupportedCultures": [ "en", "es" ],' + #13#10 +
    '    "DefaultCulture": "es"' + #13#10 +
    '  },' + #13#10 +
    '  "AllowedHosts": "*",' + #13#10 +
    '  "SettingsCors": {' + #13#10 +
    '    "AllowedOrigins": [ "http://localhost:8855", "http://localhost:5173" ]' + #13#10 +
    '  },' + #13#10 +
    '  "CacheSettings": {' + #13#10 +
    '    "Backend": "Memory"' + #13#10 +
    '  },' + #13#10 +
    '  "Jwt": {' + #13#10 +
    '    "SecretKey": "ENLIP-PROD-SECRET-KEY-CAMBIAR-MIN-32-CHARS!!",' + #13#10 +
    '    "Issuer": "enlip-api",' + #13#10 +
    '    "Audience": "enlip-web"' + #13#10 +
    '  },' + #13#10 +
    '  "Kestrel": {' + #13#10 +
    '    "Endpoints": {' + #13#10 +
    '      "Http": {' + #13#10 +
    '        "Url": "http://0.0.0.0:8855"' + #13#10 +
    '      }' + #13#10 +
    '    }' + #13#10 +
    '  }' + #13#10 +
    '}';

  SaveStringToFile(SettingsPath, JsonContent, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WriteAppSettings;
    WriteVersionJson;
  end;
end;
