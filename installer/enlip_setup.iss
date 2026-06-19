; ============================================================
; ENLIP POs — Inno Setup Script
; Empaca: Frontend Electron (win-unpacked) + Backend .NET 8
; ============================================================

#define AppName      "KAIRO POs"
#ifndef AppVersion
  #define AppVersion   "1.0.0"
#endif
#define AppPublisher "KAIRO"
#define AppId        "{{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}"
#define AppExeName   "KAIRO POs.exe"

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
Filename: "{tmp}\postgresql_installer.exe"; Parameters: "--mode unattended --unattendedmodeui minimal --disable-components stackbuilder"; StatusMsg: "Instalando PostgreSQL..."; Check: ShouldInstallPostgres
Filename: "{app}\{#AppExeName}"; Description: "Abrir {#AppName} ahora"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]

var
  PgPage: TWizardPage;
  PgHost: TEdit;
  PgPort: TEdit;
  PgDb: TEdit;
  PgUser: TEdit;
  PgPass: TEdit;
  PgHostLabel: TLabel;
  PgPortLabel: TLabel;
  PgDbLabel: TLabel;
  PgUserLabel: TLabel;
  PgPassLabel: TLabel;
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

procedure CreatePgPage;
var
  Top: Integer;
begin
  PgPage := CreateCustomPage(wpSelectDir, 'Configuracion de Base de Datos',
    'Ingresa los datos de conexion a PostgreSQL para ENLIP.');

  Top := 20;

  PgHostLabel := TLabel.Create(PgPage);
  PgHostLabel.Caption := 'Host:';
  PgHostLabel.Top := Top;
  PgHostLabel.Left := 0;
  PgHostLabel.Parent := PgPage.Surface;
  PgHost := TEdit.Create(PgPage);
  PgHost.Text := 'localhost';
  PgHost.Top := Top + 18;
  PgHost.Width := 300;
  PgHost.Left := 0;
  PgHost.Parent := PgPage.Surface;
  Top := Top + 54;

  PgPortLabel := TLabel.Create(PgPage);
  PgPortLabel.Caption := 'Puerto:';
  PgPortLabel.Top := Top;
  PgPortLabel.Left := 0;
  PgPortLabel.Parent := PgPage.Surface;
  PgPort := TEdit.Create(PgPage);
  PgPort.Text := '5432';
  PgPort.Top := Top + 18;
  PgPort.Width := 100;
  PgPort.Left := 0;
  PgPort.Parent := PgPage.Surface;
  Top := Top + 54;

  PgDbLabel := TLabel.Create(PgPage);
  PgDbLabel.Caption := 'Base de datos:';
  PgDbLabel.Top := Top;
  PgDbLabel.Left := 0;
  PgDbLabel.Parent := PgPage.Surface;
  PgDb := TEdit.Create(PgPage);
  PgDb.Text := 'ENLIP_DB';
  PgDb.Top := Top + 18;
  PgDb.Width := 300;
  PgDb.Left := 0;
  PgDb.Parent := PgPage.Surface;
  Top := Top + 54;

  PgUserLabel := TLabel.Create(PgPage);
  PgUserLabel.Caption := 'Usuario:';
  PgUserLabel.Top := Top;
  PgUserLabel.Left := 0;
  PgUserLabel.Parent := PgPage.Surface;
  PgUser := TEdit.Create(PgPage);
  PgUser.Text := 'postgres';
  PgUser.Top := Top + 18;
  PgUser.Width := 200;
  PgUser.Left := 0;
  PgUser.Parent := PgPage.Surface;
  Top := Top + 54;

  PgPassLabel := TLabel.Create(PgPage);
  PgPassLabel.Caption := 'Contrasena:';
  PgPassLabel.Top := Top;
  PgPassLabel.Left := 0;
  PgPassLabel.Parent := PgPage.Surface;
  PgPass := TEdit.Create(PgPage);
  PgPass.PasswordChar := '*';
  PgPass.Text := '';
  PgPass.Top := Top + 18;
  PgPass.Width := 200;
  PgPass.Left := 0;
  PgPass.Parent := PgPage.Surface;
end;

procedure CreateUpdateServerPage;
begin
  UpdatePage := CreateCustomPage(PgPage.ID,
    'Servidor de Actualizaciones',
    'URL desde donde la aplicacion descargara las actualizaciones automaticamente.');

  UpdateServerLabel := TLabel.Create(UpdatePage);
  UpdateServerLabel.Caption := 'URL del servidor de actualizaciones:';
  UpdateServerLabel.Top := 20;
  UpdateServerLabel.Left := 0;
  UpdateServerLabel.Parent := UpdatePage.Surface;

  UpdateServerEdit := TEdit.Create(UpdatePage);
  UpdateServerEdit.Text := 'https://updates.kairopos.com';
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
  CreatePgPage;
  CreateUpdateServerPage;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = PgPage.ID then
  begin
    if Trim(PgHost.Text) = '' then
    begin
      MsgBox('Por favor ingresa el host de PostgreSQL.', mbError, MB_OK);
      Result := False;
    end
    else if Trim(PgDb.Text) = '' then
    begin
      MsgBox('Por favor ingresa el nombre de la base de datos.', mbError, MB_OK);
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
    UpdateUrl := 'https://updates.kairopos.com';

  VersionContent :=
    '{' + #13#10 +
    '  "version": "' + '{#AppVersion}' + '",' + #13#10 +
    '  "channel": "stable",' + #13#10 +
    '  "update_server": "' + UpdateUrl + '"' + #13#10 +
    '}';

  SaveStringToFile(VersionPath, VersionContent, False);
  Log('version.json escrito con update_server: ' + UpdateUrl);
end;

procedure WriteAppSettings;
var
  SettingsPath: String;
  ConnString: String;
  JsonContent: String;
begin
  SettingsPath := ExpandConstant('{app}\api\appsettings.json');
  ConnString := 'Host=' + PgHost.Text + ';Port=' + PgPort.Text
    + ';Database=' + PgDb.Text + ';Username=' + PgUser.Text
    + ';Password=' + PgPass.Text;

  JsonContent :=
    '{' + #13#10 +
    '  "ConnectionStrings": {' + #13#10 +
    '    "ENLIP_Database": "' + ConnString + '"' + #13#10 +
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
    '  "AzureBlobStorage": {' + #13#10 +
    '    "ConnectionString": "UseDevelopmentStorage=true",' + #13#10 +
    '    "ContainerName": "enlip-pos"' + #13#10 +
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
