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

; ── PostgreSQL: dependencia bajo demanda ───────────────────────────────────
; El build ESTANDAR no embebe PostgreSQL (357 MB): lo descarga solo si hace
; falta. El build OFFLINE (compilar con /DBundlePostgres) si lo embebe, para
; instalar en PCs sin Internet. La UNICA diferencia entre ambos es de donde
; sale el instalador de PostgreSQL; todo lo demas (deteccion, instalacion,
; configuracion, validacion) es codigo compartido — ver AcquirePostgresInstaller.
;
; La version esta FIJADA a proposito: nada de "latest". URL y hash se pueden
; sobreescribir desde publish.bat con /DPostgresUrl y /DPostgresSha256 sin
; tocar este archivo.
#ifndef PostgresVersion
  #define PostgresVersion "17"
#endif
#ifndef PostgresUrl
  #define PostgresUrl "https://github.com/esbanegas/kairo-desktop/releases/download/deps-postgresql-17/postgresql_installer.exe"
#endif
#ifndef PostgresSha256
  #define PostgresSha256 "c0728faccc95ced5a280efdc32413fe35764b2302670eec72569b0fd41ac3513"
#endif
#ifndef PostgresApproxSize
  #define PostgresApproxSize "357 MB"
#endif

#define PostgresExeSource "assets\postgresql_installer.exe"
#ifdef BundlePostgres
  ; Solo el build offline exige el archivo en disco. El estandar compila sin
  ; el, que es justo lo que permite builds limpios en CI (esta en .gitignore).
  #if !FileExists(AddBackslash(SourcePath) + PostgresExeSource)
    #error Build offline solicitado (/DBundlePostgres) pero falta installer\assets\postgresql_installer.exe.
  #endif
  #define SetupSuffix "-Offline"
#else
  #define SetupSuffix ""
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
OutputBaseFilename=ENLIP_Setup_v{#AppVersion}{#SetupSuffix}
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

; -- PostgreSQL installer: SOLO en el build offline ------------------------
; En el build estandar esta entrada no existe, asi que el .exe pesa ~357 MB
; menos y PostgreSQL se descarga bajo demanda (ver AcquirePostgresInstaller).
; Un "Check:" no serviria aqui: es runtime, y el archivo quedaria embebido.
#ifdef BundlePostgres
; dontcopy (y NO DestDir): el archivo queda dentro del .exe y solo se extrae
; bajo demanda con ExtractTemporaryFile, desde el asistente. Con DestDir
; se extraeria en la fase de instalacion, que ocurre DESPUES del asistente,
; y para entonces ya seria tarde: la instalacion de PostgreSQL pasa a hacerse
; en la pagina de conexion para poder probarla y corregirla antes de terminar.
Source: "{#PostgresExeSource}"; Flags: dontcopy
#endif

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

  { ── Pagina de verificacion de PostgreSQL (nueva) ── }
  PgVerifyPage: TWizardPage;
  PgvSummary, PgvResult: TLabel;
  PgvHostLabel, PgvPortLabel, PgvUserLabel, PgvPassLabel: TLabel;
  PgvHost, PgvPort, PgvUser, PgvPass: TEdit;
  PgvTestBtn, PgvDownloadBtn, PgvSkipBtn: TNewButton;
  { Valores confirmados en esa pagina: los que se escriben en appsettings.json }
  FinalPgHost, FinalPgPort, FinalPgAdminUser, FinalPgAdminPass: String;
  PgConnectionVerified: Boolean;

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

{ ══ PostgreSQL: deteccion, validacion y obtencion del instalador ═══════════

  Este bloque encapsula TODO lo relativo a PostgreSQL para que el flujo online
  y el offline compartan la misma logica. La unica diferencia entre ambos esta
  en AcquirePostgresInstaller(): de donde sale el .exe. Instalar, detectar,
  configurar y validar es codigo comun.

  Estado de la instancia detectada. Se rellena con DetectPostgres() y lo
  consumen las paginas del asistente y WriteAppSettings. }
var
  PgDetected: Boolean;
  PgVersion: String;      { "17" }
  PgLocation: String;     { "C:\Program Files\PostgreSQL\17" }
  PgService: String;      { "postgresql-x64-17", '' si no se identifico }
  PgDetectedPort: String;         { puerto real leido de postgresql.conf, o '' }
  PgPortDetected: Boolean;{ False => PgDetectedPort es el valor por defecto, no leido }
  PgInstallAttempted: Boolean; { evita reinstalar si el usuario vuelve atras }
  PgUserSkipped: Boolean;      { eligio "Continuar sin PostgreSQL" }

{ PGPASSWORD se pasa por variable de entorno del proceso, NUNCA por linea de
  comandos: los argumentos de un proceso son visibles para cualquier usuario
  de la maquina (Administrador de tareas, WMI) y acabarian en logs. El hijo
  hereda el entorno del Setup, asi que esto basta y no deja rastro en disco. }
function SetEnvironmentVariable(lpName: String; lpValue: String): Boolean;
  external 'SetEnvironmentVariableW@kernel32.dll stdcall';

function PgDefaultPort: String;
begin
  Result := '5432';
end;

{ Ruta a una herramienta de linea de comandos dentro de la instalacion
  detectada (psql.exe vive en <Location>\bin). }
function PgBinTool(const ToolName: String): String;
begin
  if PgLocation = '' then
    Result := ''
  else
    Result := AddBackslash(PgLocation) + 'bin\' + ToolName;
end;

{ Lee el puerto de postgresql.conf. Puede fallar legitimamente: el directorio
  de datos suele estar restringido a la cuenta del servicio y a los
  Administradores, y el Setup corre como usuario estandar. Por eso el puerto
  es EDITABLE en el asistente y la verdad final la da ProbarConexion, no esto. }
function ReadPortFromConf(const DataDir: String; var Port: String): Boolean;
var
  Lines: TArrayOfString;
  I, P: Integer;
  Line, Value: String;
begin
  Result := False;
  if not FileExists(AddBackslash(DataDir) + 'postgresql.conf') then Exit;
  if not LoadStringsFromFile(AddBackslash(DataDir) + 'postgresql.conf', Lines) then Exit;

  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    Line := Trim(Lines[I]);
    if (Line = '') or (Copy(Line, 1, 1) = '#') then Continue;
    if Lowercase(Copy(Line, 1, 4)) <> 'port' then Continue;

    P := Pos('=', Line);
    if P = 0 then Continue;
    Value := Trim(Copy(Line, P + 1, Length(Line)));

    { Recortar comentario al final de la linea: "port = 5433  # comentario" }
    P := Pos('#', Value);
    if P > 0 then Value := Trim(Copy(Value, 1, P - 1));
    { Y comillas, que postgresql.conf admite }
    StringChangeEx(Value, '''', '', True);

    if (Value <> '') and (StrToIntDef(Value, 0) > 0) then
    begin
      Port := Value;
      Result := True;
      Exit;
    end;
  end;
end;

{ Identifica el servicio de Windows de la instancia. El instalador de EDB usa
  el patron postgresql-x64-<version>. Se confirma contra el registro en vez de
  asumirlo, para no mostrarle al usuario un servicio que no existe. }
function DetectPgService(const Version: String): String;
var
  Candidate: String;
begin
  Result := '';
  Candidate := 'postgresql-x64-' + Version;
  if RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\' + Candidate) then
  begin
    Result := Candidate;
    Exit;
  end;
  Candidate := 'postgresql-' + Version;
  if RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\' + Candidate) then
    Result := Candidate;
end;

{ Deteccion completa. Sustituye a la comprobacion anterior, que solo leia
  "Version" del registro y daba por hecho localhost:5432 — insuficiente en una
  maquina con varias instancias (p. ej. 16 en 5432 y 17 en 5433). }
procedure DetectPostgres;
var
  Key: String;
begin
  PgDetected := False;
  PgVersion := '';
  PgLocation := '';
  PgService := '';
  PgDetectedPort := PgDefaultPort;
  PgPortDetected := False;

  Key := 'SOFTWARE\PostgreSQL Global Development Group\PostgreSQL';
  if not (RegQueryStringValue(HKLM64, Key, 'Version', PgVersion) or
          RegQueryStringValue(HKLM32, Key, 'Version', PgVersion)) then
  begin
    Log('[PG] No se detecto PostgreSQL en el registro.');
    Exit;
  end;

  PgDetected := True;
  if not RegQueryStringValue(HKLM64, Key, 'Location', PgLocation) then
    RegQueryStringValue(HKLM32, Key, 'Location', PgLocation);

  PgService := DetectPgService(PgVersion);

  if PgLocation <> '' then
    PgPortDetected := ReadPortFromConf(AddBackslash(PgLocation) + 'data', PgDetectedPort);

  Log('[PG] Detectado: v' + PgVersion + ' | ruta=' + PgLocation +
      ' | servicio=' + PgService + ' | puerto=' + PgDetectedPort +
      ' | puerto leido de conf=' + IntToStr(Ord(PgPortDetected)));
end;

{ Texto para el asistente: que se encontro, o que no hay nada. }
function PgDetectionSummary: String;
begin
  if not PgDetected then
  begin
    Result := 'PostgreSQL no detectado en este equipo.';
    Exit;
  end;
  Result := 'PostgreSQL ' + PgVersion + ' detectado';
  if PgLocation <> '' then
    Result := Result + #13#10 + 'Ubicacion: ' + PgLocation;
  if PgService <> '' then
    Result := Result + #13#10 + 'Servicio: ' + PgService;
  if PgPortDetected then
    Result := Result + #13#10 + 'Puerto configurado: ' + PgDetectedPort
  else
    Result := Result + #13#10 + 'Puerto: ' + PgDetectedPort + ' (no se pudo leer postgresql.conf; verificalo)';
end;

{ ── Prueba de conexion real ─────────────────────────────────────────────────
  Comprueba de verdad que el host responde, el puerto responde, el usuario
  existe y la contrasena es valida — no solo que los campos no esten vacios.

  -w  nunca pedir contrasena por consola. Sin esto, con una credencial mala
      psql se quedaria esperando entrada en una ventana oculta y colgaria el
      asistente para siempre.
  -c "SELECT 1"  la consulta mas barata que prueba el circuito completo. }
function TestPgConnection(const Host, Port, User, Pass: String; var ErrMsg: String): Boolean;
var
  Psql: String;
  RC: Integer;
  Launched, IgnoredBool: Boolean;
begin
  Result := False;
  ErrMsg := '';

  Psql := PgBinTool('psql.exe');
  if (Psql = '') or (not FileExists(Psql)) then
  begin
    { El componente "Command Line Tools" del instalador de EDB es
      desmarcable. Nuestra instalacion desatendida si lo incluye, pero un
      PostgreSQL preexistente instalado a mano puede no tenerlo. No es motivo
      para bloquear: se avisa y se deja seguir. }
    ErrMsg := 'No se encontro psql.exe, asi que no se puede verificar la conexion ' +
              'automaticamente. Revisa los datos manualmente antes de continuar.';
    Exit;
  end;

  IgnoredBool := SetEnvironmentVariable('PGPASSWORD', Pass);
  try
    Launched := Exec(Psql,
      '-h ' + Host + ' -p ' + Port + ' -U ' + User + ' -d postgres -w -c "SELECT 1"',
      '', SW_HIDE, ewWaitUntilTerminated, RC);
  finally
    { Limpiar siempre: que la credencial no sobreviva en el entorno del Setup. }
    IgnoredBool := SetEnvironmentVariable('PGPASSWORD', '');
  end;

  if not Launched then
  begin
    ErrMsg := 'No se pudo ejecutar psql.exe para verificar la conexion.';
    Exit;
  end;

  if RC = 0 then
  begin
    Result := True;
    Exit;
  end;

  { Codigos de salida de psql: 1 error fatal, 2 problema de conexion
    (incluye credencial invalida), 3 error de script. }
  if RC = 2 then
    ErrMsg := 'No se pudo conectar a PostgreSQL en ' + Host + ':' + Port + '.' + #13#10 +
              'Revisa que el servicio este corriendo, que el puerto sea el correcto ' +
              'y que el usuario y la contrasena sean validos.'
  else
    ErrMsg := 'PostgreSQL rechazo la conexion (codigo ' + IntToStr(RC) + ').' + #13#10 +
              'Verifica host, puerto, usuario y contrasena.';
end;

{ Ahora se apoya en DetectPostgres (que ademas resuelve ruta, servicio y
  puerto) en vez de solo mirar si existe la clave del registro. El resultado
  para el llamador es el mismo, por eso el resto del script no cambia. }
function ShouldInstallPostgres: Boolean;
begin
  Result := True;

  if ClientRadio.Checked then
  begin
    Result := False;
    Log('Modo Cliente: no se instala PostgreSQL.');
    Exit;
  end;

  if PgDetected then
  begin
    Result := False;
    Log('PostgreSQL encontrado: v' + PgVersion + ' omitiendo instalacion.');
  end
  else
    Log('PostgreSQL no encontrado.');
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

{ ══ Obtencion e instalacion de PostgreSQL ══════════════════════════════════

  AcquirePostgresInstaller es el UNICO punto donde el sabor online y el
  offline se diferencian:

    offline (/DBundlePostgres) -> el .exe ya lo dejo [Files] en la carpeta temporal
    estandar                   -> se descarga de GitHub y se verifica SHA-256

  Todo lo que viene despues (ejecutar el instalador, re-detectar la instancia,
  configurar, validar) es identico en ambos, que es justo lo que pedia el
  requisito de no acoplar la logica al flujo online. }

var
  DownloadPage: TDownloadWizardPage;

{ Progreso de la descarga. Se muestra en MB porque el porcentaje solo no dice
  nada util con 357 MB por delante sobre un enlace lento. }
function OnPgDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  if ProgressMax > 0 then
    DownloadPage.SetText('Descargando PostgreSQL {#PostgresVersion}...',
      IntToStr(Progress div 1048576) + ' MB de ' + IntToStr(ProgressMax div 1048576) + ' MB');
  Result := True;
end;

function AcquirePostgresInstaller(var InstallerPath: String; var ErrMsg: String): Boolean;
begin
  InstallerPath := ExpandConstant('{tmp}\postgresql_installer.exe');
  ErrMsg := '';

#ifdef BundlePostgres

  { Sabor offline: el .exe viene embebido con dontcopy; se saca a la carpeta
    temporal justo ahora. Sin red. Son ~357 MB, asi que tarda unos segundos. }
  try
    ExtractTemporaryFile('postgresql_installer.exe');
    Result := FileExists(InstallerPath);
    if not Result then
      ErrMsg := 'No se pudo preparar el instalador de PostgreSQL embebido.';
  except
    Result := False;
    ErrMsg := 'No se pudo extraer el instalador de PostgreSQL embebido: ' + GetExceptionMessage;
  end;
  if Result then
    Log('[PG] Usando PostgreSQL embebido (build offline): ' + InstallerPath);

#else

  { Sabor estandar: descarga con progreso, cancelacion y verificacion SHA-256,
    todo nativo de Inno Setup 6. El hash es obligatorio: si no coincide, la
    excepcion salta y NO se ejecuta nada de lo descargado. }
  DownloadPage.Clear;
  DownloadPage.Add('{#PostgresUrl}', 'postgresql_installer.exe', '{#PostgresSha256}');
  DownloadPage.Show;
  try
    try
      DownloadPage.Download;
      Result := FileExists(InstallerPath);
      if Result then
        Log('[PG] PostgreSQL descargado y verificado (SHA-256 OK).')
      else
        ErrMsg := 'La descarga termino pero no se encontro el archivo.';
    except
      Result := False;
      ErrMsg := GetExceptionMessage;
      Log('[PG] Fallo la descarga o la verificacion: ' + ErrMsg);
    end;
  finally
    DownloadPage.Hide;
  end;

#endif
end;

{ Ejecuta el instalador de PostgreSQL. Reutiliza GetPostgresInstallerParams tal
  cual: son los mismos parametros desatendidos que ya funcionaban. Requiere
  elevacion (el .exe de EDB pide admin en su propio manifiesto), por eso
  ShellExec con verbo runas y no Exec — CreateProcess fallaria con
  ERROR_ELEVATION_REQUIRED desde un Setup no elevado. }
function RunPostgresInstaller(const InstallerPath: String; var ErrMsg: String): Boolean;
var
  ErrorCode: Integer;
begin
  ErrMsg := '';
  Log('[PG] Ejecutando instalador de PostgreSQL (se pedira elevacion)...');

  Result := ShellExec('runas', InstallerPath, GetPostgresInstallerParams(''),
                      '', SW_SHOW, ewWaitUntilTerminated, ErrorCode);
  if not Result then
  begin
    if ErrorCode = 1223 then
      ErrMsg := 'No se otorgaron permisos de administrador, asi que PostgreSQL no se instalo.'
    else
      ErrMsg := 'No se pudo iniciar el instalador de PostgreSQL (codigo ' + IntToStr(ErrorCode) + ').';
    Log('[PG] ' + ErrMsg);
  end;
end;

{ Orquesta el ciclo completo: obtener -> instalar -> volver a detectar.
  Se vuelve a detectar para quedarse con la ruta, el servicio y el puerto
  REALES de lo que acaba de instalarse, en vez de darlos por supuestos. }
function EnsurePostgresInstalled(var ErrMsg: String): Boolean;
var
  InstallerPath: String;
begin
  Result := False;
  ErrMsg := '';

  if not AcquirePostgresInstaller(InstallerPath, ErrMsg) then Exit;
  if not RunPostgresInstaller(InstallerPath, ErrMsg) then Exit;

  PgInstallAttempted := True;

  DetectPostgres;
  if not PgDetected then
  begin
    ErrMsg := 'El instalador de PostgreSQL termino, pero no se pudo confirmar que ' +
              'quedara instalado. Verificalo antes de continuar.';
    Log('[PG] ' + ErrMsg);
    Exit;
  end;

  Result := True;
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

{ ══ Pagina de verificacion de PostgreSQL ═══════════════════════════════════

  Pagina NUEVA, insertada entre la configuracion de base de datos y el resumen
  final. Se agrego aparte en vez de meter controles en PgModePage/PgConfigPage
  para no tocar el layout de unas paginas que ya funcionan.

  Hace tres cosas que antes no existian:
    1. Muestra la instancia realmente detectada (version, ruta, servicio,
       puerto), en vez de asumir localhost:5432.
    2. Si no hay PostgreSQL, ofrece descargarlo o continuar sin el.
    3. Obliga a probar la conexion de verdad antes de seguir, para que una
       contrasena mal tecleada se vea aqui y no como un fallo incomprensible
       la primera vez que se abre Kairo.

  Los valores confirmados aqui son los que WriteAppSettings termina escribiendo. }


{ Rellena la pagina con lo detectado y con lo que el usuario eligio en las
  paginas anteriores. Se llama cada vez que la pagina se muestra, para que
  refleje el resultado de una instalacion de PostgreSQL hecha desde aqui. }
procedure RefreshPgVerifyPage;
begin
  PgvSummary.Caption := PgDetectionSummary;

  { Botones segun el estado: si hay PostgreSQL solo tiene sentido probar; si
    no lo hay, ofrecer instalarlo o seguir sin el. }
  PgvTestBtn.Visible := PgDetected;
  PgvDownloadBtn.Visible := (not PgDetected) and (not PgUserSkipped);
  PgvSkipBtn.Visible := (not PgDetected) and (not PgUserSkipped);

  PgvHost.Enabled := PgDetected;
  PgvPort.Enabled := PgDetected;
  PgvUser.Enabled := PgDetected;
  PgvPass.Enabled := PgDetected;

  if PgUserSkipped then
    PgvResult.Caption := 'Continuaras sin PostgreSQL. Kairo se instalara, pero no ' +
                         'podra usar la base local hasta que instales y configures PostgreSQL.';

  { Prefill: en modo automatico se fija host/usuario y se usa el puerto REAL
    detectado (antes estaba cableado a 5432, lo que rompia en equipos con
    varias instancias). En modo personalizado se arrastra lo ya tecleado. }
  if AutoModeRadio.Checked then
  begin
    if PgvHost.Text = '' then PgvHost.Text := 'localhost';
    if PgvPort.Text = '' then PgvPort.Text := PgDetectedPort;
    if PgvUser.Text = '' then PgvUser.Text := 'postgres';
    if PgvPass.Text = '' then PgvPass.Text := PgAdminPassAutoMode.Text;
  end
  else
  begin
    if PgvHost.Text = '' then PgvHost.Text := Trim(PgHost.Text);
    if PgvPort.Text = '' then PgvPort.Text := Trim(PgPort.Text);
    if PgvUser.Text = '' then PgvUser.Text := Trim(PgAdminUser.Text);
    if PgvPass.Text = '' then PgvPass.Text := PgAdminPass.Text;
  end;
end;

{ Guarda lo confirmado en la pagina: es la fuente de verdad para
  WriteAppSettings. }
procedure CommitPgVerifyValues;
begin
  FinalPgHost := Trim(PgvHost.Text);
  FinalPgPort := Trim(PgvPort.Text);
  FinalPgAdminUser := Trim(PgvUser.Text);
  FinalPgAdminPass := PgvPass.Text;
end;

procedure OnPgTestClick(Sender: TObject);
var
  ErrMsg: String;
begin
  PgvResult.Caption := 'Probando conexion...';
  if TestPgConnection(Trim(PgvHost.Text), Trim(PgvPort.Text),
                      Trim(PgvUser.Text), PgvPass.Text, ErrMsg) then
  begin
    PgConnectionVerified := True;
    CommitPgVerifyValues;
    PgvResult.Caption := 'Conexion correcta: PostgreSQL respondio en ' +
                         Trim(PgvHost.Text) + ':' + Trim(PgvPort.Text) + '.';
  end
  else
  begin
    PgConnectionVerified := False;
    PgvResult.Caption := ErrMsg;
  end;
end;

procedure OnPgDownloadClick(Sender: TObject);
var
  ErrMsg: String;
begin
  if EnsurePostgresInstalled(ErrMsg) then
  begin
    { Tras instalar, la instancia nueva ya trae su ruta/servicio/puerto reales:
      se limpian los campos para que RefreshPgVerifyPage los vuelva a llenar. }
    PgvHost.Text := '';
    PgvPort.Text := '';
    PgvUser.Text := '';
    RefreshPgVerifyPage;
    PgvResult.Caption := 'PostgreSQL ' + PgVersion + ' se instalo correctamente. ' +
                         'Ahora prueba la conexion.';
  end
  else
  begin
    RefreshPgVerifyPage;
    PgvResult.Caption := ErrMsg;
  end;
end;

procedure OnPgSkipClick(Sender: TObject);
begin
  if MsgBox('Kairo se instalara, pero NO podra usar la base de datos local hasta ' +
            'que instales y configures PostgreSQL manualmente.' + #13#10#13#10 +
            'La instalacion NO quedara lista para usarse.' + #13#10#13#10 +
            'Deseas continuar sin PostgreSQL?', mbConfirmation, MB_YESNO) <> IDYES then
    Exit;

  PgUserSkipped := True;
  PgConnectionVerified := False;
  Log('[PG] El usuario eligio continuar sin PostgreSQL.');
  RefreshPgVerifyPage;
end;

procedure CreatePgVerifyPage;
begin
  PgVerifyPage := CreateCustomPage(PgConfigPage.ID,
    'Conexion con PostgreSQL',
    'Verifica los datos de conexion antes de continuar.');

  PgvSummary := TLabel.Create(PgVerifyPage);
  PgvSummary.AutoSize := False;
  PgvSummary.WordWrap := True;
  PgvSummary.Top := 0;
  PgvSummary.Left := 0;
  PgvSummary.Width := 410;
  PgvSummary.Height := 58;
  PgvSummary.Parent := PgVerifyPage.Surface;

  PgvHostLabel := TLabel.Create(PgVerifyPage);
  PgvHostLabel.Caption := 'Host:';
  PgvHostLabel.Top := 66;
  PgvHostLabel.Left := 0;
  PgvHostLabel.Parent := PgVerifyPage.Surface;

  PgvHost := TEdit.Create(PgVerifyPage);
  PgvHost.Top := 82;
  PgvHost.Left := 0;
  PgvHost.Width := 170;
  PgvHost.Parent := PgVerifyPage.Surface;

  PgvPortLabel := TLabel.Create(PgVerifyPage);
  PgvPortLabel.Caption := 'Puerto:';
  PgvPortLabel.Top := 66;
  PgvPortLabel.Left := 190;
  PgvPortLabel.Parent := PgVerifyPage.Surface;

  PgvPort := TEdit.Create(PgVerifyPage);
  PgvPort.Top := 82;
  PgvPort.Left := 190;
  PgvPort.Width := 80;
  PgvPort.Parent := PgVerifyPage.Surface;

  PgvUserLabel := TLabel.Create(PgVerifyPage);
  PgvUserLabel.Caption := 'Usuario:';
  PgvUserLabel.Top := 110;
  PgvUserLabel.Left := 0;
  PgvUserLabel.Parent := PgVerifyPage.Surface;

  PgvUser := TEdit.Create(PgVerifyPage);
  PgvUser.Top := 126;
  PgvUser.Left := 0;
  PgvUser.Width := 170;
  PgvUser.Parent := PgVerifyPage.Surface;

  PgvPassLabel := TLabel.Create(PgVerifyPage);
  PgvPassLabel.Caption := 'Contrasena:';
  PgvPassLabel.Top := 110;
  PgvPassLabel.Left := 190;
  PgvPassLabel.Parent := PgVerifyPage.Surface;

  PgvPass := TEdit.Create(PgVerifyPage);
  PgvPass.PasswordChar := '*';
  PgvPass.Top := 126;
  PgvPass.Left := 190;
  PgvPass.Width := 170;
  PgvPass.Parent := PgVerifyPage.Surface;

  PgvTestBtn := TNewButton.Create(PgVerifyPage);
  PgvTestBtn.Caption := 'Probar conexion';
  PgvTestBtn.Top := 160;
  PgvTestBtn.Left := 0;
  PgvTestBtn.Width := 120;
  PgvTestBtn.Height := 25;
  PgvTestBtn.OnClick := @OnPgTestClick;
  PgvTestBtn.Parent := PgVerifyPage.Surface;

  PgvDownloadBtn := TNewButton.Create(PgVerifyPage);
  PgvDownloadBtn.Caption := 'Descargar e instalar';
  PgvDownloadBtn.Top := 160;
  PgvDownloadBtn.Left := 130;
  PgvDownloadBtn.Width := 130;
  PgvDownloadBtn.Height := 25;
  PgvDownloadBtn.OnClick := @OnPgDownloadClick;
  PgvDownloadBtn.Parent := PgVerifyPage.Surface;

  PgvSkipBtn := TNewButton.Create(PgVerifyPage);
  PgvSkipBtn.Caption := 'Continuar sin PostgreSQL';
  PgvSkipBtn.Top := 160;
  PgvSkipBtn.Left := 268;
  PgvSkipBtn.Width := 142;
  PgvSkipBtn.Height := 25;
  PgvSkipBtn.OnClick := @OnPgSkipClick;
  PgvSkipBtn.Parent := PgVerifyPage.Surface;

  PgvResult := TLabel.Create(PgVerifyPage);
  PgvResult.AutoSize := False;
  PgvResult.WordWrap := True;
  PgvResult.Caption := '';
  PgvResult.Top := 190;
  PgvResult.Left := 0;
  PgvResult.Width := 410;
  PgvResult.Height := 34;
  PgvResult.Parent := PgVerifyPage.Surface;
end;

procedure CreateUpdateServerPage;
begin
  UpdatePage := CreateCustomPage(PgVerifyPage.ID,
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

  { Deteccion temprana: las paginas de base de datos se construyen a
    continuacion y necesitan el puerto e info de la instancia para
    prerellenarse con valores reales en vez de un 5432 asumido. }
  DetectPostgres;
  PgInstallAttempted := False;
  PgUserSkipped := False;

  DownloadPage := CreateDownloadPage(
    'Descargando PostgreSQL',
    'Kairo necesita PostgreSQL {#PostgresVersion} y no se encontro en este equipo.',
    @OnPgDownloadProgress);

  CreateInstallModePage;
  CreateClientConfigPage;
  CreatePgModePage;
  CreatePgConfigPage;
  CreatePgVerifyPage;
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
       (PageID = PgVerifyPage.ID) or
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

{ Refresca la pagina de verificacion cada vez que se entra en ella: puede
  llegarse despues de instalar PostgreSQL desde la propia pagina, o tras
  volver atras a cambiar el modo. }
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = PgVerifyPage.ID then
    RefreshPgVerifyPage;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ErrMsg: String;
begin
  Result := True;

  { ── Pagina de verificacion de PostgreSQL ──────────────────────────────────
    No se deja avanzar sin una conexion probada. La excepcion es haber elegido
    explicitamente "Continuar sin PostgreSQL", y el caso en que no hay psql.exe
    para verificar: ahi se avisa y se permite seguir, porque bloquear por una
    herramienta ausente seria peor que el problema. }
  if CurPageID = PgVerifyPage.ID then
  begin
    if PgUserSkipped then Exit;

    if not PgDetected then
    begin
      MsgBox('Todavia no hay PostgreSQL en este equipo.' + #13#10#13#10 +
             'Usa "Descargar e instalar", o "Continuar sin PostgreSQL" si vas a ' +
             'configurarlo por tu cuenta mas tarde.', mbError, MB_OK);
      Result := False;
      Exit;
    end;

    if not PgConnectionVerified then
    begin
      if TestPgConnection(Trim(PgvHost.Text), Trim(PgvPort.Text),
                          Trim(PgvUser.Text), PgvPass.Text, ErrMsg) then
      begin
        PgConnectionVerified := True;
        CommitPgVerifyValues;
      end
      else
      begin
        PgvResult.Caption := ErrMsg;
        if Pos('psql.exe', ErrMsg) > 0 then
        begin
          { Sin psql no se puede verificar: avisar y dejar decidir. }
          Result := MsgBox(ErrMsg + #13#10#13#10 + 'Deseas continuar de todas formas?',
                           mbConfirmation, MB_YESNO) = IDYES;
          if Result then CommitPgVerifyValues;
        end
        else
        begin
          MsgBox('No se pudo conectar a PostgreSQL.' + #13#10#13#10 + ErrMsg + #13#10#13#10 +
                 'Corrige host, puerto, usuario o contrasena y vuelve a probar.',
                 mbError, MB_OK);
          Result := False;
        end;
      end;
      Exit;
    end;

    CommitPgVerifyValues;
    Exit;
  end;

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
    Port := PgDefaultPort;
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

  { Los valores realmente verificados en la pagina de conexion mandan sobre los
    de arriba. Esto corrige el puerto que estaba cableado a 5432: en un equipo
    con varias instancias de PostgreSQL (p. ej. 16 en 5432 y 17 en 5433) ese
    valor apuntaria a la instancia equivocada. Si el usuario eligio continuar
    sin PostgreSQL no hay nada confirmado, y se respeta lo anterior en vez de
    escribir una configuracion inventada. }
  if (not PgUserSkipped) and (FinalPgHost <> '') then
  begin
    Host := FinalPgHost;
    Port := FinalPgPort;
    AdminUser := FinalPgAdminUser;
    AdminPass := FinalPgAdminPass;
    Log('[PG] appsettings.json usara la conexion verificada: ' + Host + ':' + Port +
        ' (usuario ' + AdminUser + ')');
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

{ PostgreSQL ya NO se instala aqui: se movio al asistente (ver la pagina de
  verificacion), que es donde el usuario puede probar la conexion y corregir
  los datos antes de que la instalacion termine. Aqui solo queda el firewall,
  que no necesita interaccion. }
procedure RunElevatedPhase;
begin
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
