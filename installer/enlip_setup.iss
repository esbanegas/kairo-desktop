; ============================================================
; ENLIP POs — Inno Setup Script
; Empaca: Frontend Electron (win-unpacked) + Backend .NET 8
; ============================================================

#define AppName      "KAIRO POs"
#ifndef AppVersion
  #define AppVersion   "1.0.0"
#endif
#ifndef AppChannel
  #define AppChannel   "production"
#endif
#define AppPublisher "KAIRO"
; El GUID crudo se define aparte porque [Code] necesita construir con el la ruta
; de la clave de desinstalacion. AppId lo deriva duplicando la llave inicial,
; que es como Inno escapa un "{" literal. Una sola fuente de verdad: si el GUID
; cambia, la deteccion de instalaciones previas lo sigue automaticamente.
#define AppIdRaw     "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
#define AppId        "{{" + AppIdRaw + "}"
#define AppExeName   "KAIRO POs.exe"
#ifndef UpdateServerUrl
  #define UpdateServerUrl "https://raw.githubusercontent.com/esbanegas/kairo-desktop/main/installer/updates"
#endif

; kairo-updater.exe se valida en tiempo de COMPILACION: si falta, el
; instalador generado no podria aplicar ninguna actualizacion, asi que es
; preferible fallar el build a producir un .exe silenciosamente roto.
; Generalo primero con: updater\build-updater.bat
#define UpdaterExeSource "assets\kairo-updater\kairo-updater.exe"
#if !FileExists(AddBackslash(SourcePath) + UpdaterExeSource)
  #error kairo-updater.exe no encontrado en installer\assets\kairo-updater\. Ejecuta updater\build-updater.bat antes de compilar el instalador.
#endif

#define FrontendDir  "..\..\acg-web\release\win-unpacked"
#define BackendDir   "..\..\enlip-services\ENLIPWebApi\bin\Release\net8.0\publish"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
; Instalación por-usuario (como VS Code/Discord/Slack), no Program Files:
; el auto-updater sobrescribe app.asar/api/* sin privilegios elevados solo
; si {app} es escribible sin UAC. {autopf} (Program Files) lo requeriría en
; cada actualización; {localappdata}\Programs no, nunca.
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename=ENLIP_Setup_v{#AppVersion}
OutputDir=output
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0
; ── Principio del modelo de instalación ────────────────────────────────────
; El Setup corre SIEMPRE como el usuario que va a operar el POS, nunca
; elevado; solo las operaciones que de verdad exigen privilegios (instalar
; PostgreSQL, abrir el puerto en el firewall) se elevan puntualmente desde
; [Code] con ShellExec('runas', ...).
;
; Por qué: un Setup elevado resuelve {localappdata}, {userdesktop} y la clave
; de desinstalación al perfil de la cuenta que proporcionó las credenciales
; UAC — el supervisor o técnico — y no al del cajero. Kairo terminaría en un
; perfil al que el operador no tiene acceso. Con "lowest" todos esos recursos
; per-user resuelven al usuario correcto POR CONSTRUCCIÓN: no hay que leer
; ProfileList, adivinar rutas de perfil ni reparar ACLs después.
;
; Esto es compatible con el escenario cajero-estándar + supervisor-admin:
; el cajero lanza el Setup, y el UAC aparece solo en el momento de instalar
; PostgreSQL. Ver InitializeSetup, que bloquea el arranque elevado porque
; "lowest" por sí solo no lo impide.
;
; Verificado sobre los ACL por defecto de Windows 11: un usuario estándar
; puede crear C:\ProgramData\KairoPOS (Users tiene AD/crear-subdirectorios) y
; queda como propietario, así que también puede fijar su DACL; y el proceso
; elevado puede leer {tmp} (Administradores hereda Full en el Temp de cada
; usuario), que es de donde se lanza el instalador de PostgreSQL.
;
; Ojo: mover {app} a Program Files NO es alternativa, porque entonces cada
; auto-actualización pediría UAC (ver DefaultDirName arriba).
PrivilegesRequired=lowest
SetupIconFile=assets\enlip.ico
UninstallDisplayIcon={app}\{#AppExeName}
DisableProgramGroupPage=yes
; El frontend (KAIRO POs.exe) y el backend (ENLIPWebApi.exe, detached) pueden
; seguir corriendo cuando se reinstala manualmente sobre una instalación
; existente. Sin esto, Inno Setup falla al sobrescribir esos archivos con un
; error nativo de "archivo en uso". CloseApplications usa Restart Manager
; para detectar cualquier proceso con archivos abiertos bajo {app} y cerrarlo
; automáticamente antes de copiar.
CloseApplications=force
CloseApplicationsFilter=*.exe
RestartApplications=no

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
; Sin Check: el archivo se embebe en tiempo de compilacion y SIEMPRE debe
; extraerse. (Antes tenia Check: UpdaterExists, que evaluaba {src} -- la
; carpeta desde donde el usuario final ejecuta el Setup, NO la carpeta de
; assets del build. En cualquier maquina limpia esa ruta no existe, el Check
; devolvia False y kairo-updater.exe nunca se instalaba: las actualizaciones
; se descargaban y verificaban bien, pero al aplicarlas Electron caia en el
; fallback "kairo-updater.exe no encontrado" y solo se reiniciaba sin
; reemplazar nada.) La existencia se valida ahora en tiempo de compilacion.
Source: "{#UpdaterExeSource}"; DestDir: "{app}\updater"; Flags: ignoreversion

; ── PostgreSQL installer — extracted to temp only when needed ───────────────
Source: "assets\postgresql_installer.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: ShouldInstallBackend

[Icons]
; Accesos directos per-user: con PrivilegesRequired=lowest, {group} resuelve
; solo al menú Inicio del usuario y {autodesktop} a su escritorio. Antes era
; {commondesktop} ("para todos los usuarios"), que además de requerir admin
; apuntaría a un {app} dentro de un perfil que los demás usuarios no pueden
; leer — un acceso directo visible para todos pero funcional para uno solo.
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; PostgreSQL ya NO se lanza desde aquí: las entradas de [Run] heredan los
; privilegios del Setup, que ahora es no elevado. Se instala desde [Code]
; (ver RunElevatedPhase), que es donde se puede pedir elevación puntual.
Filename: "{app}\{#AppExeName}"; Description: "Abrir {#AppName} ahora"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Dirs]
; Sin "Permissions:" a propósito. Fijar un DACL requiere ser propietario del
; directorio, y hay un caso donde no lo somos: al migrar desde alpha.8 o
; anterior, C:\ProgramData\KairoPOS ya existe creado por aquel Setup elevado
; (propietario: la cuenta administradora), y la desinstalación no lo borra
; porque contiene datos. El Setup nuevo corre como el cajero, así que
; intentar reescribir ese DACL fallaría.
;
; No hace falta: los dos caminos ya quedan correctos sin tocar permisos.
;   - Instalación nueva: el cajero crea las carpetas y hereda CREATOR OWNER
;     (control total) del ACL por defecto de C:\ProgramData, que además
;     permite a los usuarios estándar crear subdirectorios ahí.
;   - Migración desde alpha.8: las carpetas ya existen con users-modify
;     aplicado por el instalador viejo, así que el cajero ya puede escribir.
; Inno simplemente no hace nada si el directorio ya existe.
;
; Es la opción más segura: elimina la única operación que podía fallar y no
; modifica ni borra ningún dato existente.
;
; Límite conocido y aceptado: en una instalación nueva, otro usuario de
; Windows en la misma PC solo tendría lectura sobre estas carpetas. El modelo
; soportado es un usuario de POS por equipo, así que no aplica.
Name: "{commonappdata}\KairoPOS"
Name: "{commonappdata}\KairoPOS\Files"
Name: "{commonappdata}\KairoPOS\backups"
Name: "{commonappdata}\KairoPOS\state"

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

{ ── Arranque: guards previos al asistente ────────────────────────────────── }

{ Clave de desinstalación que escribía el modelo anterior. Con
  PrivilegesRequired=admin, Inno corría en "administrative install mode" y
  registraba la desinstalación en HKLM; el modelo nuevo (lowest) la registra
  en HKCU. Esa diferencia es justo lo que permite distinguir una instalación
  vieja de una reinstalación normal del mismo usuario, sin enumerar perfiles
  ni tocar nada ajeno: basta leer HKLM, que un usuario estándar puede leer. }
function LegacyUninstallKey: String;
begin
  Result := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{' +
            '{#AppIdRaw}' + '}_is1';
end;

function FindLegacyMachineWideInstall(var Version: String; var Location: String): Boolean;
var
  Key: String;
begin
  Key := LegacyUninstallKey;
  Result := True;

  { Se consultan ambas vistas del registro: el modelo anterior compilaba con
    ArchitecturesInstallIn64BitMode=x64 (vista de 64 bits), pero una alpha
    más antigua pudo haber quedado registrada en la de 32. }
  if RegQueryStringValue(HKLM64, Key, 'DisplayVersion', Version) or
     RegQueryStringValue(HKLM32, Key, 'DisplayVersion', Version) then
  begin
    if not RegQueryStringValue(HKLM64, Key, 'InstallLocation', Location) then
      RegQueryStringValue(HKLM32, Key, 'InstallLocation', Location);
    Exit;
  end;

  { Sin DisplayVersion la entrada igual cuenta como instalación previa. }
  if RegKeyExists(HKLM64, Key) or RegKeyExists(HKLM32, Key) then
  begin
    Version := '(desconocida)';
    RegQueryStringValue(HKLM64, Key, 'InstallLocation', Location);
    Exit;
  end;

  Result := False;
end;

function InitializeSetup: Boolean;
var
  LegacyVersion, LegacyLocation, Msg: String;
begin
  Result := True;

  { ── Aviso: el Setup se está ejecutando elevado ──────────────────────────
    PrivilegesRequired=lowest hace que el camino correcto sea el predeterminado
    (Inno ya no auto-eleva, así que un doble clic normal nunca da token
    elevado, ni siquiera a un administrador). Pero si alguien usa "Ejecutar
    como administrador" a propósito, Kairo se instalaría en el perfil de esa
    cuenta — el bug original.

    Es un AVISO con opción de continuar, no un bloqueo: elevado no siempre
    está mal. Un administrador instalando para sí mismo, o cualquier usuario
    en una PC con UAC deshabilitado (donde todo admin corre siempre elevado),
    están en el caso correcto y deben poder seguir. Mostrar la ruta real
    resuelta deja que quien está frente a la pantalla decida en un vistazo,
    sin que el instalador tenga que averiguar qué usuario "debería" recibir
    la instalación.

    Se usa IsAdmin y NO IsAdminInstallMode: con "lowest" el install mode es
    siempre no administrativo aunque el proceso venga elevado. }
  if IsAdmin and (not WizardSilent) then
  begin
    Msg := 'Este instalador se está ejecutando con permisos de administrador.' + #13#10#13#10 +
           'Kairo POS se instalará en:' + #13#10 +
           '    ' + ExpandConstant('{localappdata}\Programs\{#AppName}') + #13#10#13#10 +
           'Si esa NO es la cuenta de Windows que va a utilizar el punto de venta, ' +
           'cancela e inicia el instalador desde esa cuenta, con doble clic normal. ' +
           'El instalador pedirá credenciales de administrador por su cuenta si hace ' +
           'falta instalar PostgreSQL o abrir el firewall.' + #13#10#13#10 +
           '¿Deseas continuar de todas formas?';
    if MsgBox(Msg, mbConfirmation, MB_YESNO) <> IDYES then
    begin
      Log('Cancelado por el usuario tras el aviso de ejecucion elevada.');
      Result := False;
      Exit;
    end;
    Log('Advertencia: Setup elevado; el usuario eligio continuar.');
  end;

  { ── Instalación previa del modelo anterior ──────────────────────────────
    Solo informa y se detiene. No desinstala ni modifica nada: migrar las
    alphas anteriores es una tarea de despliegue aparte. }
  if FindLegacyMachineWideInstall(LegacyVersion, LegacyLocation) then
  begin
    Msg := 'Se detectó una instalación anterior de Kairo POS (versión ' + LegacyVersion + ')';
    if LegacyLocation <> '' then
      Msg := Msg + ' en:' + #13#10 + '    ' + LegacyLocation;
    Msg := Msg + '.' + #13#10#13#10 +
           'Esa instalación se hizo con el modelo anterior, que la dejaba en el perfil ' +
           'de la cuenta administradora en lugar del usuario del POS. No se puede ' +
           'actualizar sobre ella.' + #13#10#13#10 +
           'Desinstala Kairo POS desde "Agregar o quitar programas" y vuelve a ejecutar ' +
           'este instalador. Tus datos no se pierden: la base de datos y los archivos en ' +
           'C:\ProgramData\KairoPOS no se tocan al desinstalar.';
    if not WizardSilent then
      MsgBox(Msg, mbError, MB_OK);
    Log('Abortado: instalación previa detectada en HKLM (v' + LegacyVersion + ', ' + LegacyLocation + ').');
    Result := False;
    Exit;
  end;
end;

{ ── Mode helpers ─────────────────────────────────────────────────────────── }

function IsClientMode: Boolean;
begin
  Result := ClientRadio.Checked;
end;

function ShouldInstallBackend: Boolean;
begin
  Result := not ClientRadio.Checked;
end;

{ Extraído de ShouldInstallPostgres para poder reusarlo como VERIFICACIÓN
  después de la instalación elevada: ShellExec no devuelve el exit code del
  proceso lanzado (a diferencia de Exec), así que el resultado real se
  comprueba por evidencia — que la clave exista ahora y antes no. Leer HKLM
  no requiere privilegios. }
function IsPostgresInstalled(var InstalledVersion: String): Boolean;
var
  PostgresKey: String;
begin
  PostgresKey := 'SOFTWARE\PostgreSQL Global Development Group\PostgreSQL';
  Result := RegQueryStringValue(HKLM64, PostgresKey, 'Version', InstalledVersion) or
            RegQueryStringValue(HKLM32, PostgresKey, 'Version', InstalledVersion);
end;

function ShouldInstallPostgres: Boolean;
var
  InstalledVersion: String;
begin
  Result := True;

  if ClientRadio.Checked then
  begin
    Result := False;
    Log('Modo Cliente: no se instala PostgreSQL.');
    Exit;
  end;

  if IsPostgresInstalled(InstalledVersion) then
  begin
    Result := False;
    Log('PostgreSQL encontrado: v' + InstalledVersion + ' omitiendo instalacion.');
  end
  else
    Log('PostgreSQL no encontrado, se instalara.');
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

{ ── Fase elevada ──────────────────────────────────────────────────────────
  Las dos únicas operaciones de toda la instalación que exigen privilegios.
  Se lanzan con ShellExec + verbo 'runas', que dispara el UAC en ese momento
  concreto: el cajero ve el prompt y el supervisor teclea sus credenciales.

  Van como DOS llamadas separadas y NO envueltas en un cmd.exe /C que las
  encadene en un solo prompt. El motivo es el superpassword de PostgreSQL: lo
  teclea el usuario, así que puede contener ", &, ^ o % — pasarlo por el shell
  lo expondría a interpolación y rompería (o algo peor) la instalación. Como
  parámetro directo de ShellExec no lo interpreta ningún shell, igual que
  antes cuando era una entrada de [Run]. El costo es un segundo prompt UAC,
  pero solo en la combinación modo Servidor + PostgreSQL ausente. }

const
  FirewallRuleName = 'Kairo POS API';

function IsFirewallRulePresent: Boolean;
var
  ResultCode: Integer;
begin
  { Listar reglas no requiere privilegios; netsh devuelve <> 0 si no hay
    ninguna coincidencia. Sirve para verificar el resultado de la llamada
    elevada, que por usar ShellExec no entrega exit code. }
  Result := Exec('netsh',
    'advfirewall firewall show rule name="' + FirewallRuleName + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure InstallPostgresElevated;
var
  InstallerPath, InstalledVersion: String;
  ErrorCode: Integer;
begin
  InstallerPath := ExpandConstant('{tmp}\postgresql_installer.exe');
  if not FileExists(InstallerPath) then
  begin
    Log('ERROR: no se encontro el instalador de PostgreSQL en ' + InstallerPath);
    MsgBox('No se encontró el instalador de PostgreSQL.' + #13#10#13#10 +
           'Kairo quedó instalado, pero necesitarás instalar PostgreSQL manualmente ' +
           'antes de usarlo.', mbError, MB_OK);
    Exit;
  end;

  WizardForm.StatusLabel.Caption := 'Instalando PostgreSQL (requiere permisos de administrador)...';
  Log('Solicitando elevacion para instalar PostgreSQL...');

  if not ShellExec('runas', InstallerPath, GetPostgresInstallerParams(''),
                   '', SW_SHOW, ewWaitUntilTerminated, ErrorCode) then
  begin
    { 1223 = ERROR_CANCELLED: el UAC fue rechazado o cerrado. Merece un
      mensaje distinto al de un fallo real del instalador. }
    if ErrorCode = 1223 then
      MsgBox('No se otorgaron permisos de administrador, así que PostgreSQL no se instaló.' + #13#10#13#10 +
             'Kairo POS quedó instalado correctamente, pero no funcionará hasta que ' +
             'PostgreSQL esté disponible. Vuelve a ejecutar este instalador con un ' +
             'administrador disponible para completar ese paso.', mbError, MB_OK)
    else
      MsgBox('No se pudo iniciar el instalador de PostgreSQL (código ' + IntToStr(ErrorCode) + ').' + #13#10#13#10 +
             'Kairo POS quedó instalado, pero necesitarás instalar PostgreSQL manualmente.',
             mbError, MB_OK);
    Log('PostgreSQL: fallo al elevar/lanzar, ErrorCode=' + IntToStr(ErrorCode));
    Exit;
  end;

  { Verificación por evidencia (ver IsPostgresInstalled). }
  if IsPostgresInstalled(InstalledVersion) then
    Log('PostgreSQL instalado correctamente: v' + InstalledVersion)
  else
  begin
    Log('ADVERTENCIA: el instalador de PostgreSQL termino pero la clave de registro sigue ausente.');
    MsgBox('El instalador de PostgreSQL terminó, pero no se pudo confirmar que quedara instalado.' + #13#10#13#10 +
           'Kairo POS quedó instalado. Verifica PostgreSQL antes de usar el sistema.',
           mbInformation, MB_OK);
  end;
end;

procedure OpenFirewallPortElevated;
var
  ErrorCode: Integer;
begin
  if IsFirewallRulePresent then
  begin
    Log('Firewall: la regla "' + FirewallRuleName + '" ya existe, no se solicita elevacion.');
    Exit;
  end;

  WizardForm.StatusLabel.Caption := 'Configurando el firewall (requiere permisos de administrador)...';
  Log('Solicitando elevacion para abrir el puerto 8855...');

  if not ShellExec('runas', 'netsh',
       'advfirewall firewall add rule name="' + FirewallRuleName +
       '" dir=in action=allow protocol=TCP localport=8855',
       '', SW_HIDE, ewWaitUntilTerminated, ErrorCode) then
  begin
    Log('Firewall: fallo al elevar/lanzar, ErrorCode=' + IntToStr(ErrorCode));
    MsgBox('No se pudo abrir el puerto 8855 en el firewall de Windows.' + #13#10#13#10 +
           'Kairo POS quedó instalado, pero las terminales en modo Cliente no podrán ' +
           'conectarse a este servidor hasta que se abra ese puerto.', mbError, MB_OK);
    Exit;
  end;

  if IsFirewallRulePresent then
    Log('Firewall: regla agregada para el puerto 8855.')
  else
  begin
    Log('ADVERTENCIA: netsh termino pero la regla de firewall no aparece.');
    MsgBox('No se pudo confirmar la regla de firewall para el puerto 8855.' + #13#10#13#10 +
           'Verifícala manualmente si las terminales Cliente no logran conectarse.',
           mbInformation, MB_OK);
  end;
end;

procedure RunElevatedPhase;
begin
  if ShouldInstallPostgres then
    InstallPostgresElevated;

  if ServerRadio.Checked then
    OpenFirewallPortElevated;
end;

procedure LockDownFileToAdmins(const FilePath: String);
var
  ResultCode: Integer;
begin
  { ProgramData hereda un ACL que da lectura al grupo "Users" por defecto,
    lo que expondria la contrasena en texto plano a cualquier cuenta local
    de Windows. Se quita la herencia y se otorga acceso unicamente a
    Administradores (S-1-5-32-544) y SYSTEM (S-1-5-18) - SIDs "well-known",
    validos en cualquier idioma de Windows. }
  Exec('icacls.exe',
    '"' + FilePath + '" /inheritance:r /grant:r "*S-1-5-32-544:(F)" /grant:r "*S-1-5-18:(F)"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if ResultCode <> 0 then
    Log('ADVERTENCIA: No se pudieron restringir permisos de ' + FilePath + ' (icacls exit code ' + IntToStr(ResultCode) + ').')
  else
    Log('Permisos restringidos a Administradores/SYSTEM: ' + FilePath);
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
  { Segundo caso de compatibilidad con alpha.8: si ya existe un
    admin_credentials.txt de aquella instalación, quedó con su ACL restringido
    a Administradores/SYSTEM y sobrevivió a la desinstalación (está en
    ProgramData, que no se borra). El cajero no puede sobrescribirlo. No se
    borra ni se le tocan los permisos — se escribe junto a la app, que es un
    lugar al que el cajero sí tiene acceso, y se deja constancia en el log. }
  if not SaveStringToFile(CredPath, Content, False) then
  begin
    Log('No se pudo escribir ' + CredPath + ' (probablemente un archivo de una ' +
        'instalacion anterior con permisos restringidos). Usando ruta alternativa.');
    CredPath := ExpandConstant('{app}\admin_credentials.txt');
    if not SaveStringToFile(CredPath, Content, False) then
    begin
      Log('ERROR: tampoco se pudo escribir ' + CredPath + '. No se guardaron las credenciales.');
      Exit;
    end;
  end;

  LockDownFileToAdmins(CredPath);
  Log('Credenciales de kairo_user guardadas en: ' + CredPath);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    { La fase elevada va PRIMERO, mientras el supervisor que teclea las
      credenciales UAC sigue presente frente a la máquina. Si falla no se
      aborta la instalación: los archivos de configuración se escriben igual,
      para que quede recuperable instalando PostgreSQL a mano después. }
    RunElevatedPhase;

    WriteInstallConfig;
    if not ClientRadio.Checked then
    begin
      WriteAppSettings;
      WriteVersionJson;
      if AutoModeRadio.Checked then
        WriteCredentialsFile;
    end;
  end;
end;
