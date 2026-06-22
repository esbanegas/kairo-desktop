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
; ── Frontend (Electron) — always installed ─────────────────────────────────
Source: "{#FrontendDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb"

; ── Backend (.NET 8) — skipped in Client mode ──────────────────────────────
Source: "{#BackendDir}\*"; DestDir: "{app}\api"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb,appsettings*.json,appsettings - Copy*.json,web.config"; Check: ShouldInstallBackend
; appsettings.json: onlyifdoesntexist preserves DB credentials on reinstall.
Source: "{#BackendDir}\appsettings.json"; DestDir: "{app}\api"; Flags: ignoreversion onlyifdoesntexist; Check: ShouldInstallBackend

; ── Version manifest (read by backend and Electron) ────────────────────────
Source: "version.json"; DestDir: "{app}"; Flags: ignoreversion

; ── Kairo Updater (external process that replaces files after Electron exits)
Source: "assets\kairo-updater\kairo-updater.exe"; DestDir: "{app}\updater"; Flags: ignoreversion; Check: UpdaterExists

; ── PostgreSQL installer — extracted to temp only when needed ───────────────
Source: "assets\postgresql_installer.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: ShouldInstallBackend

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\postgresql_installer.exe"; Parameters: "{code:GetPostgresInstallerParams}"; StatusMsg: "Instalando PostgreSQL..."; Check: ShouldInstallPostgres
Filename: "{app}\{#AppExeName}"; Description: "Abrir {#AppName} ahora"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Dirs]
Name: "{commonappdata}\KairoPOS"; Permissions: users-modify
Name: "{commonappdata}\KairoPOS\Files"; Permissions: users-modify
Name: "{commonappdata}\KairoPOS\backups"; Permissions: users-modify
Name: "{commonappdata}\KairoPOS\state"; Permissions: users-modify

[Code]

var
  { ── Auto-mode: app user password (random, generated once) }
  AutoAppPass: String;

  { ── Installation mode page ── }
  InstallModePage: TWizardPage;
  StandaloneRadio: TRadioButton;
  ServerRadio: TRadioButton;
  ClientRadio: TRadioButton;
  StandaloneLabel: TLabel;
  ServerLabel: TLabel;
  ClientLabel: TLabel;

  { ── Client server URL page ── }
  ClientConfigPage: TWizardPage;
  ServerIpEdit: TEdit;
  ServerIpLabel: TLabel;
  ServerIpNote: TLabel;

  { ── Database mode page ── }
  PgModePage: TWizardPage;
  AutoModeRadio: TRadioButton;
  CustomModeRadio: TRadioButton;
  AutoModeLabel: TLabel;
  CustomModeLabel: TLabel;

  { ── PostgreSQL custom config page ── }
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

  { ── Auto-mode admin password field (shown on PgModePage) }
  PgAdminPassAutoMode: TEdit;
  PgAdminPassAutoModeLabel: TLabel;
  PgAdminPassAutoModeNote: TLabel;

  { ── Update Server page ── }
  UpdatePage: TWizardPage;
  UpdateServerEdit: TEdit;
  UpdateServerLabel: TLabel;
  UpdateServerNote: TLabel;

{ ── Mode helpers ─────────────────────────────────────────────────────────── }

function IsClientMode: Boolean;
begin
  Result := ClientRadio.Checked;
end;

function ShouldInstallBackend: Boolean;
begin
  Result := not ClientRadio.Checked;
end;

function ShouldInstallPostgres: Boolean;
var
  PostgresKey: String;
  InstalledVersion: String;
begin
  Result := True;

  if ClientRadio.Checked then
  begin
    Result := False;
    Log('Modo Cliente: no se instala PostgreSQL.');
    Exit;
  end;

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
    AdminPass := PgAdminPassAutoMode.Text
  else
    AdminPass := PgAdminPass.Text;

  Result := '--mode unattended --unattendedmodeui minimal --disable-components stackbuilder --superpassword "' + AdminPass + '"';
end;

{ ── Random password generator ───────────────────────────────────────────── }

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

function GetAutoAppPass: String;
begin
  if AutoAppPass = '' then
    AutoAppPass := GenerateRandomPassword(16);
  Result := AutoAppPass;
end;

{ ── Page creation ────────────────────────────────────────────────────────── }

procedure CreateInstallModePage;
begin
  InstallModePage := CreateCustomPage(wpSelectDir,
    'Modo de Instalación',
    'Seleccione el tipo de instalación según el rol de este equipo.');

  StandaloneRadio := TRadioButton.Create(InstallModePage);
  StandaloneRadio.Caption := 'Standalone (todo en un solo equipo)';
  StandaloneRadio.Font.Style := [fsBold];
  StandaloneRadio.Top := 16;
  StandaloneRadio.Left := 10;
  StandaloneRadio.Width := 420;
  StandaloneRadio.Checked := True;
  StandaloneRadio.Parent := InstallModePage.Surface;

  StandaloneLabel := TLabel.Create(InstallModePage);
  StandaloneLabel.Caption :=
    'Instala todo: Electron, backend .NET, PostgreSQL y servicios.' + #13#10 +
    'Ideal para negocios pequeños con una sola caja.';
  StandaloneLabel.Top := 34;
  StandaloneLabel.Left := 30;
  StandaloneLabel.Width := 400;
  StandaloneLabel.Height := 30;
  StandaloneLabel.Parent := InstallModePage.Surface;

  ServerRadio := TRadioButton.Create(InstallModePage);
  ServerRadio.Caption := 'Servidor (base de datos + API central)';
  ServerRadio.Font.Style := [fsBold];
  ServerRadio.Top := 80;
  ServerRadio.Left := 10;
  ServerRadio.Width := 420;
  ServerRadio.Parent := InstallModePage.Surface;

  ServerLabel := TLabel.Create(InstallModePage);
  ServerLabel.Caption :=
    'Instala el backend, PostgreSQL y la interfaz de administración.' + #13#10 +
    'Este equipo será el servidor central al que se conectarán los clientes.';
  ServerLabel.Top := 98;
  ServerLabel.Left := 30;
  ServerLabel.Width := 400;
  ServerLabel.Height := 30;
  ServerLabel.Parent := InstallModePage.Surface;

  ClientRadio := TRadioButton.Create(InstallModePage);
  ClientRadio.Caption := 'Cliente (caja o punto de venta remoto)';
  ClientRadio.Font.Style := [fsBold];
  ClientRadio.Top := 144;
  ClientRadio.Left := 10;
  ClientRadio.Width := 420;
  ClientRadio.Parent := InstallModePage.Surface;

  ClientLabel := TLabel.Create(InstallModePage);
  ClientLabel.Caption :=
    'Instala únicamente Electron. Se conecta al servidor Kairo en la red local.' + #13#10 +
    'No instala PostgreSQL ni el backend — requiere un servidor activo.';
  ClientLabel.Top := 162;
  ClientLabel.Left := 30;
  ClientLabel.Width := 400;
  ClientLabel.Height := 30;
  ClientLabel.Parent := InstallModePage.Surface;
end;

procedure CreateClientConfigPage;
begin
  ClientConfigPage := CreateCustomPage(InstallModePage.ID,
    'Conexión al Servidor',
    'Ingresa la dirección IP del servidor Kairo en tu red local.');

  ServerIpLabel := TLabel.Create(ClientConfigPage);
  ServerIpLabel.Caption := 'Dirección IP del servidor:';
  ServerIpLabel.Top := 20;
  ServerIpLabel.Left := 0;
  ServerIpLabel.Parent := ClientConfigPage.Surface;

  ServerIpEdit := TEdit.Create(ClientConfigPage);
  ServerIpEdit.Text := '192.168.1.';
  ServerIpEdit.Top := 38;
  ServerIpEdit.Left := 0;
  ServerIpEdit.Width := 220;
  ServerIpEdit.Parent := ClientConfigPage.Surface;

  ServerIpNote := TLabel.Create(ClientConfigPage);
  ServerIpNote.Caption :=
    'Ejemplo: 192.168.1.50' + #13#10 + #13#10 +
    'Puedes encontrar la IP del servidor en:' + #13#10 +
    '  • El equipo servidor → ejecuta "ipconfig" en CMD' + #13#10 +
    '  • El panel de administración de tu router' + #13#10 + #13#10 +
    'El cliente se conectará en: http://[IP]:8855';
  ServerIpNote.Top := 74;
  ServerIpNote.Left := 0;
  ServerIpNote.Width := 420;
  ServerIpNote.AutoSize := False;
  ServerIpNote.Height := 120;
  ServerIpNote.Parent := ClientConfigPage.Surface;
end;

procedure CreatePgModePage;
begin
  PgModePage := CreateCustomPage(ClientConfigPage.ID,
    'Modo de Configuración de Base de Datos',
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
  AutoModeLabel.Caption :=
    'Configura PostgreSQL automáticamente.' + #13#10 +
    'Se crean la base "KAIRO_DB" y el usuario "kairo_user" con contraseña segura.';
  AutoModeLabel.Top := 38;
  AutoModeLabel.Left := 30;
  AutoModeLabel.Width := 400;
  AutoModeLabel.Height := 28;
  AutoModeLabel.Parent := PgModePage.Surface;

  PgAdminPassAutoModeLabel := TLabel.Create(PgModePage);
  PgAdminPassAutoModeLabel.Caption := 'Contraseña del administrador PostgreSQL (usuario postgres):';
  PgAdminPassAutoModeLabel.Top := 72;
  PgAdminPassAutoModeLabel.Left := 30;
  PgAdminPassAutoModeLabel.Width := 380;
  PgAdminPassAutoModeLabel.Parent := PgModePage.Surface;

  PgAdminPassAutoMode := TEdit.Create(PgModePage);
  PgAdminPassAutoMode.PasswordChar := '*';
  PgAdminPassAutoMode.Text := '';
  PgAdminPassAutoMode.Top := 90;
  PgAdminPassAutoMode.Left := 30;
  PgAdminPassAutoMode.Width := 250;
  PgAdminPassAutoMode.Parent := PgModePage.Surface;

  PgAdminPassAutoModeNote := TLabel.Create(PgModePage);
  PgAdminPassAutoModeNote.Caption :=
    'Primera instalacion: define la contrasena del superusuario postgres.' + #13#10 +
    'PostgreSQL ya instalado: ingresa tu contrasena actual de postgres.';
  PgAdminPassAutoModeNote.Top := 115;
  PgAdminPassAutoModeNote.Left := 30;
  PgAdminPassAutoModeNote.Width := 380;
  PgAdminPassAutoModeNote.Height := 28;
  PgAdminPassAutoModeNote.Parent := PgModePage.Surface;

  CustomModeRadio := TRadioButton.Create(PgModePage);
  CustomModeRadio.Caption := 'Modo personalizado (avanzado)';
  CustomModeRadio.Font.Style := [fsBold];
  CustomModeRadio.Top := 152;
  CustomModeRadio.Left := 10;
  CustomModeRadio.Width := 400;
  CustomModeRadio.Parent := PgModePage.Surface;

  CustomModeLabel := TLabel.Create(PgModePage);
  CustomModeLabel.Caption :=
    'Permite especificar manualmente las credenciales del' + #13#10 +
    'administrador y los detalles de la base de datos y usuario de la aplicacion.';
  CustomModeLabel.Top := 170;
  CustomModeLabel.Left := 30;
  CustomModeLabel.Width := 400;
  CustomModeLabel.Height := 30;
  CustomModeLabel.Parent := PgModePage.Surface;
end;

procedure CreatePgConfigPage;
begin
  PgConfigPage := CreateCustomPage(PgModePage.ID, 'Configuración Personalizada de PostgreSQL',
    'Ingresa las credenciales de administrador y de la aplicación.');

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
  CreateInstallModePage;
  CreateClientConfigPage;
  CreatePgModePage;
  CreatePgConfigPage;
  CreateUpdateServerPage;
end;

{ ── Page navigation ──────────────────────────────────────────────────────── }

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;

  { Client mode: skip all DB and update server pages }
  if ClientRadio.Checked then
  begin
    if (PageID = PgModePage.ID) or
       (PageID = PgConfigPage.ID) or
       (PageID = UpdatePage.ID) then
      Result := True;
    Exit;
  end;

  { Non-client modes: skip the client server URL page }
  if PageID = ClientConfigPage.ID then
  begin
    Result := True;
    Exit;
  end;

  { Auto DB mode: skip the custom credentials page }
  if PageID = PgConfigPage.ID then
    Result := AutoModeRadio.Checked;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if CurPageID = ClientConfigPage.ID then
  begin
    if Trim(ServerIpEdit.Text) = '' then
    begin
      MsgBox('Por favor ingresa la dirección IP del servidor.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;

  if CurPageID = PgModePage.ID then
  begin
    if AutoModeRadio.Checked and (Trim(PgAdminPassAutoMode.Text) = '') then
    begin
      MsgBox('Por favor ingresa la contraseña del administrador de PostgreSQL.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;

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

{ ── Post-install file writers ────────────────────────────────────────────── }

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
  LanMode: String;
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
    AppPass := GetAutoAppPass;
    AdminUser := 'postgres';
    AdminPass := PgAdminPassAutoMode.Text;
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

  { Server mode: enable LanMode so clients on the LAN can connect }
  if ServerRadio.Checked then
    LanMode := 'true'
  else
    LanMode := 'false';

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
    '    "TimeZone": "America/Tegucigalda"' + #13#10 +
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
    '    "LanMode": ' + LanMode + ',' + #13#10 +
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

procedure WriteInstallConfig;
var
  ConfigPath: String;
  Mode: String;
  ServerUrl: String;
  JsonContent: String;
begin
  ConfigPath := ExpandConstant('{app}\kairo-install.json');

  if ClientRadio.Checked then
  begin
    Mode := 'client';
    ServerUrl := 'http://' + Trim(ServerIpEdit.Text) + ':8855';
    JsonContent :=
      '{' + #13#10 +
      '  "mode": "' + Mode + '",' + #13#10 +
      '  "serverUrl": "' + ServerUrl + '"' + #13#10 +
      '}';
  end
  else if ServerRadio.Checked then
  begin
    Mode := 'server';
    JsonContent :=
      '{' + #13#10 +
      '  "mode": "' + Mode + '"' + #13#10 +
      '}';
  end
  else
  begin
    Mode := 'standalone';
    JsonContent :=
      '{' + #13#10 +
      '  "mode": "' + Mode + '"' + #13#10 +
      '}';
  end;

  SaveStringToFile(ConfigPath, JsonContent, False);
  Log('kairo-install.json escrito: mode=' + Mode);
end;

procedure OpenFirewallPort;
var
  ResultCode: Integer;
begin
  Exec('netsh',
    'advfirewall firewall add rule name="Kairo POS API" dir=in action=allow protocol=TCP localport=8855',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Log('Firewall: regla agregada para puerto 8855, resultado: ' + IntToStr(ResultCode));
end;

procedure WriteCredentialsFile;
var
  CredPath: String;
  Content: String;
begin
  CredPath := ExpandConstant('{commonappdata}\KairoPOS\admin_credentials.txt');
  Content :=
    '===== Kairo POS — Credenciales de la Aplicacion =====' + #13#10 +
    'Guarda este archivo en un lugar seguro.' + #13#10 + #13#10 +
    'Usuario de la Aplicacion (uso diario y acceso en pgAdmin):' + #13#10 +
    '  Host      : localhost' + #13#10 +
    '  Puerto    : 5432' + #13#10 +
    '  Base datos: KAIRO_DB' + #13#10 +
    '  Usuario   : kairo_user' + #13#10 +
    '  Contrasena: ' + GetAutoAppPass + #13#10 + #13#10 +
    'Como conectarte en pgAdmin:' + #13#10 +
    '  1. Abre pgAdmin' + #13#10 +
    '  2. Agrega un nuevo servidor (Add New Server)' + #13#10 +
    '  3. En Connection: usa los datos de arriba' + #13#10 +
    '  4. Solo veras la base de datos KAIRO_DB' + #13#10 + #13#10 +
    'NOTA: La contrasena del superusuario "postgres" es la que' + #13#10 +
    'definiste durante la instalacion. Guardala por separado.' + #13#10;
  SaveStringToFile(CredPath, Content, False);
  Log('Credenciales de kairo_user guardadas en: ' + CredPath);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WriteInstallConfig;
    if not ClientRadio.Checked then
    begin
      WriteAppSettings;
      WriteVersionJson;
      if AutoModeRadio.Checked then
        WriteCredentialsFile;
    end;
    if ServerRadio.Checked then
      OpenFirewallPort;
  end;

  if CurStep = ssDone then
  begin
    if (not ClientRadio.Checked) and AutoModeRadio.Checked then
      MsgBox(
        'Instalacion completada.' + #13#10 + #13#10 +
        'Se generaron credenciales unicas para PostgreSQL.' + #13#10 +
        'Guardalas en un lugar seguro:' + #13#10 + #13#10 +
        'C:\ProgramData\KairoPOS\admin_credentials.txt',
        mbInformation, MB_OK);
  end;
end;
