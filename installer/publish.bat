@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM KAIRO POS - Pipeline de Compilacion y Publicacion
REM ============================================================

set "ROOT=%~dp0..\.."
set "FRONTEND=%ROOT%\acg-web"
set "BACKEND=%ROOT%\enlip-services\ENLIPWebApi"
set "INSTALLER=%~dp0"
if "%INSTALLER:~-1%"=="\" set "INSTALLER=%INSTALLER:~0,-1%"

REM Canal opcional como 2do argumento (alpha|beta|production). Si se omite
REM o es invalido, se pregunta de forma interactiva mas adelante.
set "CHANNEL="
if not "%~2"=="" (
    for %%X in (alpha beta production) do if /i "%~2"=="%%X" set "CHANNEL=%%X"
    if not defined CHANNEL (
        echo [ERROR] Canal '%~2' invalido. Debe ser: alpha, beta o production.
        pause
        exit /b 1
    )
)

if "%~1"=="" goto :menu
if "%~1"=="--build-only" goto :dispatch_build
if "%~1"=="-b" goto :dispatch_build
if "%~1"=="--publish" goto :dispatch_publish
if "%~1"=="-p" goto :dispatch_publish
if "%~1"=="--all" goto :dispatch_all
if "%~1"=="-a" goto :dispatch_all
if "%~1"=="--verify" goto :dispatch_verify
if "%~1"=="-v" goto :dispatch_verify

echo Uso: publish.bat --build-only [alpha^|beta^|production]   [Solo empaqueta y genera manifiesto]
echo      publish.bat --publish     [alpha^|beta^|production]   [Crea release en GitHub y sube assets]
echo      publish.bat --all         [alpha^|beta^|production]   [Compila y publica todo]
echo      publish.bat --verify      [alpha^|beta^|production]   [Solo lectura: valida manifest/tag/Release/assets]
echo.
echo Si se omite el canal se preguntara de forma interactiva.
echo.
pause
exit /b 1

:dispatch_build
if not defined CHANNEL call :prompt_channel
goto :build

:dispatch_publish
if not defined CHANNEL call :prompt_channel
goto :publish

:dispatch_all
if not defined CHANNEL call :prompt_channel
goto :all

:dispatch_verify
if not defined CHANNEL call :prompt_channel
goto :verify

:prompt_channel
echo.
echo ============================================================
echo  KAIRO POS - Pipeline de Compilacion y Publicacion
echo ============================================================
echo.
echo  Seleccione el canal:
echo.
echo   [1] Alpha
echo   [2] Beta
echo   [3] Production
echo.
choice /c 123 /n /m "Seleccione una opcion [1-3]: "
if errorlevel 3 (set "CHANNEL=production") else if errorlevel 2 (set "CHANNEL=beta") else (set "CHANNEL=alpha")
goto :eof

:menu
call :prompt_channel
echo.
echo ============================================================
echo  Canal seleccionado: !CHANNEL!
echo ============================================================
echo.
echo  [1] Compilar paquetes (--build-only)
echo  [2] Publicar Release a GitHub (--publish)
echo  [3] Compilar y Publicar todo (--all)
echo  [4] Verificar consistencia (solo lectura: manifest/tag/Release/assets)
echo  [5] Salir
echo.
choice /c 12345 /n /m "Selecciona una opcion [1-5]: "
if errorlevel 5 exit /b 0
if errorlevel 4 goto :verify
if errorlevel 3 goto :all
if errorlevel 2 goto :publish
if errorlevel 1 goto :build
goto :menu

:all
echo.
echo ============================================================
echo  Canal: !CHANNEL! / Operacion: Build + Publish
echo ============================================================
call :build_process
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo en la fase de compilacion.
    pause
    exit /b 1
)
call :publish_process
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo en la fase de publicacion.
    pause
    exit /b 1
)
pause
goto :eof

:build
echo.
echo ============================================================
echo  Canal: !CHANNEL! / Operacion: Build
echo ============================================================
call :build_process
pause
goto :eof

:publish
echo.
echo ============================================================
echo  Canal: !CHANNEL! / Operacion: Publish
echo ============================================================
call :publish_process
pause
goto :eof

:verify
echo.
echo ============================================================
echo  Canal: !CHANNEL! / Operacion: Verificar consistencia (solo lectura)
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%\verify-manifest.ps1" -channel "%CHANNEL%"
pause
goto :eof


REM ============================================================
REM FASE DE BUILD
REM ============================================================
:build_process
echo ============================================================
echo  FASE BUILD (--build-only)
echo ============================================================

REM 1. Leer Configuracion (el canal ya viene resuelto en %CHANNEL%)
for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).version"') do set "VERSION=%%V"
for /f "tokens=*" %%O in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\build.config.json' | ConvertFrom-Json).repo_owner"') do set "REPO_OWNER=%%O"
for /f "tokens=*" %%N in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\build.config.json' | ConvertFrom-Json).repo_name"') do set "REPO_NAME=%%N"
for /f "tokens=*" %%U in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\build.config.json' | ConvertFrom-Json).github_base_url"') do set "GITHUB_BASE_URL=%%U"
for /f "tokens=*" %%D in ('powershell -NoProfile -Command "[DateTime]::UtcNow.ToString(\"yyyy-MM-ddTHH:mm:ssZ\")"') do set "BUILD_DATE=%%D"

REM Obtener la version SemVer resuelta
set "FULL_VERSION="
for /f "tokens=*" %%F in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%\get-version.ps1" -version "%VERSION%" -channel "%CHANNEL%"') do set "FULL_VERSION=%%F"
if "%FULL_VERSION%"=="" (
    echo [ERROR] No se pudo determinar la version o el tag ya existe.
    call :restore_version
    exit /b 1
)

REM Hacer copia de seguridad de version.json y sobrescribir temporalmente con
REM la version y el canal resueltos (asi las instalaciones en modo Cliente,
REM que copian este archivo tal cual, tambien quedan con el canal correcto).
copy /y "%INSTALLER%\version.json" "%INSTALLER%\version.json.bak" >nul
powershell -NoProfile -Command "$json = Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json; $json.version = '%FULL_VERSION%'; $json.channel = '%CHANNEL%'; $json | ConvertTo-Json -Depth 10 | Set-Content '%INSTALLER%\version.json'"

REM Reemplazar variables en GITHUB_BASE_URL usando FULL_VERSION
set "BASE_URL=!GITHUB_BASE_URL:{repo_owner}=%REPO_OWNER%!"
set "BASE_URL=!BASE_URL:{repo_name}=%REPO_NAME%!"
set "BASE_URL=!BASE_URL:{version}=%FULL_VERSION%!"

REM Verificar que kairo-updater.exe exista en assets
if not exist "%INSTALLER%\assets\kairo-updater\kairo-updater.exe" (
    echo [INFO] kairo-updater.exe no encontrado en assets. Compilando automaticamente...
    call "%ROOT%\kairo-desktop\updater\build-updater.bat"
)

echo Canal: %CHANNEL%
echo Version Base: %VERSION%
echo Version Compilada (SemVer): %FULL_VERSION%
echo Base URL: %BASE_URL%

if exist "%INSTALLER%\output" (
    echo [INFO] Limpiando carpeta de salida anterior...
    rmdir /s /q "%INSTALLER%\output"
)

set "OUTPUT=%INSTALLER%\output\updates\%FULL_VERSION%"
if not exist "%OUTPUT%" mkdir "%OUTPUT%"

REM 2. Compilar Frontend (Electron) y Zip
echo [1/4] Construyendo frontend (Vite/Electron)...
cd /d "%FRONTEND%"
if exist "release" rmdir /s /q "release"
call pnpm run build:electron
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo la compilacion del frontend.
    call :restore_version
    exit /b 1
)

REM Obtener nombre del producto/ejecutable desde package.json
for /f "tokens=*" %%P in ('powershell -NoProfile -Command "(Get-Content '%FRONTEND%\package.json' | ConvertFrom-Json).build.productName"') do set "PRODUCT_NAME=%%P"
if "!PRODUCT_NAME!"=="" set "PRODUCT_NAME=KAIRO POs"

set "EXE_PATH=release\win-unpacked\!PRODUCT_NAME!.exe"
set "ASAR_PATH=release\win-unpacked\resources\app.asar"

if not exist "!EXE_PATH!" (
    echo [ERROR] No se genero el ejecutable '!PRODUCT_NAME!.exe' en release\win-unpacked.
    echo Revisa el log de electron-builder para ver detalles del fallo.
    call :restore_version
    exit /b 1
)

if not exist "!ASAR_PATH!" (
    echo [ERROR] No se genero el recurso 'resources\app.asar' en release\win-unpacked.
    echo Revisa el log de electron-builder para ver detalles del fallo.
    call :restore_version
    exit /b 1
)

echo [OK] Frontend compilado y verificado correctamente (!PRODUCT_NAME!.exe).

set "FRONTEND_ZIP=%OUTPUT%\frontend.zip"
if exist "%FRONTEND_ZIP%" del "%FRONTEND_ZIP%"
REM Comprimir app.asar en lugar de dist/*
powershell -NoProfile -Command "Compress-Archive -Path '%ASAR_PATH%' -DestinationPath '%FRONTEND_ZIP%' -Force"
echo [OK] frontend.zip (empaquetado con app.asar)


REM 3. Compilar Backend y Zip
echo [2/4] Construyendo backend (.NET)...
cd /d "%BACKEND%"

if exist "bin\Release\net8.0\publish" (
    echo [INFO] Limpiando publicacion anterior del backend...
    rmdir /s /q "bin\Release\net8.0\publish"
)

dotnet publish -c Release -o "bin\Release\net8.0\publish" -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo la compilacion del backend.
    call :restore_version
    exit /b 1
)
set "BACKEND_ZIP=%OUTPUT%\backend.zip"
set "BACKEND_PUBLISH=%BACKEND%\bin\Release\net8.0\publish"
if exist "%BACKEND_ZIP%" del "%BACKEND_ZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%BACKEND_PUBLISH%\*' -DestinationPath '%BACKEND_ZIP%' -Force"
echo [OK] backend.zip

REM 4. Compilar Instalador
echo [3/4] Compilando instalador (Inno Setup)...
cd /d "%INSTALLER%"

set "ISCC=C:\Users\ebanegas\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
if not exist "!ISCC!" (
    set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
)
if not exist "!ISCC!" (
    for /f "tokens=*" %%I in ('where iscc.exe 2^>nul') do set "ISCC=%%I"
)
if not exist "!ISCC!" (
    echo [ERROR] No se encontro ISCC.exe. Asegurate de tener Inno Setup 6 instalado.
    call :restore_version
    exit /b 1
)
echo [INFO] Usando: !ISCC!

"!ISCC!" /DAppVersion="%FULL_VERSION%" /DAppChannel="%CHANNEL%" /DUpdateServerUrl="https://raw.githubusercontent.com/%REPO_OWNER%/%REPO_NAME%/main/installer/updates" "%INSTALLER%\enlip_setup.iss"
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo Inno Setup.
    call :restore_version
    exit /b 1
)
set "INSTALLER_EXE=%INSTALLER%\output\ENLIP_Setup_v%FULL_VERSION%.exe"
set "TARGET_INSTALLER_EXE=%OUTPUT%\KairoSetup.exe"
copy /y "%INSTALLER_EXE%" "%TARGET_INSTALLER_EXE%" >nul
echo [OK] KairoSetup.exe

REM 5. Calcular Hashes SHA256
echo [4/4] Calculando Hashes...
for /f "tokens=1" %%H in ('powershell -NoProfile -Command "(Get-FileHash '%FRONTEND_ZIP%' -Algorithm SHA256).Hash.ToLower()"') do set "FRONTEND_SHA=%%H"
for /f "tokens=1" %%H in ('powershell -NoProfile -Command "(Get-FileHash '%BACKEND_ZIP%' -Algorithm SHA256).Hash.ToLower()"') do set "BACKEND_SHA=%%H"
for /f "tokens=1" %%H in ('powershell -NoProfile -Command "(Get-FileHash '%TARGET_INSTALLER_EXE%' -Algorithm SHA256).Hash.ToLower()"') do set "INSTALLER_SHA=%%H"

REM 6. Generar latest-<channel>.json (KAIRO UPDATE MANIFEST V1.0)
set "MANIFEST=%OUTPUT%\latest-%CHANNEL%.json"
(
  echo {
  echo   "schema": "kairo.update.manifest",
  echo   "schema_version": "1.0.0",
  echo   "app": {
  echo     "name": "Kairo POS",
  echo     "version": "%FULL_VERSION%",
  echo     "channel": "%CHANNEL%",
  echo     "release_date": "%BUILD_DATE%"
  echo   },
  echo   "distribution": {
  echo     "provider": "github_releases",
  echo     "base_url": "%BASE_URL%"
  echo   },
  echo   "files": {
  echo     "installer": {
  echo       "name": "KairoSetup.exe",
  echo       "sha256": "%INSTALLER_SHA%"
  echo     },
  echo     "frontend": {
  echo       "name": "frontend.zip",
  echo       "sha256": "%FRONTEND_SHA%"
  echo     },
  echo     "backend": {
  echo       "name": "backend.zip",
  echo       "sha256": "%BACKEND_SHA%"
  echo     }
  echo   },
  echo   "update_policy": {
  echo     "mandatory": false,
  echo     "min_supported_version": "1.0.0",
  echo     "restart_required": true
  echo   }
  echo }
) > "%MANIFEST%"
if not exist "%MANIFEST%" (
    echo [ERROR] No se pudo escribir el manifiesto "%MANIFEST%".
    call :restore_version
    exit /b 1
)
echo %FULL_VERSION%> "%INSTALLER%\output\build_version.txt"
echo %CHANNEL%> "%INSTALLER%\output\build_channel.txt"
echo.
echo ============================================================
echo  Build Completado Exitosamente
echo  Canal: %CHANNEL%
echo  Resultados en: %OUTPUT%
echo ============================================================
call :restore_version
goto :eof


REM ============================================================
REM FASE DE PUBLISH
REM ============================================================
:publish_process
echo ============================================================
echo  FASE PUBLISH (--publish)
echo ============================================================

if /i "!CHANNEL!"=="production" (
    echo.
    echo ============================================================
    echo  ADVERTENCIA: estas a punto de publicar al canal PRODUCTION.
    echo  Esto sera visible para todos los clientes reales.
    echo ============================================================
    choice /c SN /n /m "Confirmas que deseas publicar a Production? [S/N]: "
    if errorlevel 2 (
        echo [INFO] Publicacion a Production cancelada por el usuario.
        exit /b 1
    )
)

for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).version"') do set "VERSION=%%V"

set "FULL_VERSION="
if exist "%INSTALLER%\output\build_version.txt" (
    for /f "usebackq tokens=*" %%F in ("%INSTALLER%\output\build_version.txt") do set "FULL_VERSION=%%F"
    if defined FULL_VERSION set "FULL_VERSION=!FULL_VERSION: =!"
    echo [INFO] Detectada version compilada previa: !FULL_VERSION!

    REM Verificar que la compilacion local se haya hecho para el MISMO canal
    REM que se acaba de seleccionar. Evita publicar un build de Alpha al
    REM canal de Production (o viceversa) por error de seleccion de menu.
    set "BUILD_CHANNEL="
    if exist "%INSTALLER%\output\build_channel.txt" (
        for /f "usebackq tokens=*" %%C in ("%INSTALLER%\output\build_channel.txt") do set "BUILD_CHANNEL=%%C"
        if defined BUILD_CHANNEL set "BUILD_CHANNEL=!BUILD_CHANNEL: =!"
    )
    if not "!BUILD_CHANNEL!"=="!CHANNEL!" (
        echo [ERROR] La compilacion local en '%INSTALLER%\output' fue hecha para el canal '!BUILD_CHANNEL!' pero seleccionaste '!CHANNEL!'.
        echo [ERROR] Vuelve a ejecutar 'Compilar' con el canal correcto antes de publicar. No se toco git ni GitHub.
        exit /b 1
    )
)

if "!FULL_VERSION!"=="" (
    echo [INFO] No se encontro registro de compilacion previa. Resolviendo version...
    for /f "tokens=*" %%F in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%\get-version.ps1" -version "%VERSION%" -channel "%CHANNEL%"') do set "FULL_VERSION=%%F"
)

if "!FULL_VERSION!"=="" (
    echo [ERROR] No se pudo determinar la version de la publicacion.
    exit /b 1
)

set "OUTPUT=%INSTALLER%\output\updates\%FULL_VERSION%"

if not exist "%OUTPUT%\latest-%CHANNEL%.json" (
    echo [ERROR] No existe el build local en '%OUTPUT%'. Ejecuta la opcion de Compilar primero.
    exit /b 1
)

echo [1/2] Verificando GitHub CLI...
gh --version >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] GitHub CLI [gh] no esta instalado o autenticado.
    exit /b 1
)

echo [2/2] Publicando Release v%FULL_VERSION% (canal: %CHANNEL%) en GitHub...
cd /d "%INSTALLER%\.."

git rev-parse "v%FULL_VERSION%" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    git tag -a v%FULL_VERSION% -m "Release v%FULL_VERSION%"
    if !ERRORLEVEL! NEQ 0 (
        echo [ERROR] Fallo la creacion del tag v%FULL_VERSION%.
        exit /b 1
    )
) else (
    echo [INFO] El tag v%FULL_VERSION% ya existe localmente. Omitiendo creacion...
)
git push origin v%FULL_VERSION%
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo el push del tag v%FULL_VERSION% a GitHub. Abortando antes de crear la release.
    exit /b 1
)

set "PRERELEASE_FLAG="
if "%CHANNEL%"=="alpha" set "PRERELEASE_FLAG=--prerelease"
if "%CHANNEL%"=="beta" set "PRERELEASE_FLAG=--prerelease"

gh release create v%FULL_VERSION% ^
    "%OUTPUT%\KairoSetup.exe" ^
    "%OUTPUT%\frontend.zip" ^
    "%OUTPUT%\backend.zip" ^
    "%OUTPUT%\latest-%CHANNEL%.json" ^
    --title "Kairo POS v%FULL_VERSION%" ^
    --notes "Nueva actualizacion de Kairo POS v%FULL_VERSION% (canal: %CHANNEL%)" ^
    !PRERELEASE_FLAG!

if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo la creacion de la release en GitHub.
    exit /b 1
)

echo [3/3] Publicando manifiesto de actualizacion en git...
if not exist "%INSTALLER%\updates" mkdir "%INSTALLER%\updates"
copy /y "%OUTPUT%\latest-%CHANNEL%.json" "%INSTALLER%\updates\latest-%CHANNEL%.json" >nul

echo [INFO] Sincronizando con origin antes de commitear el manifiesto...
git pull --rebase --autostash
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] git pull --rebase fallo. Resuelve conflictos manualmente y reintenta el publish.
    echo [ERROR] El release v%FULL_VERSION% YA fue creado en GitHub, pero el manifiesto de actualizacion NO se ha publicado todavia.
    exit /b 1
)

git add "%INSTALLER%\updates\latest-%CHANNEL%.json"
git commit -m "Update manifest for v%FULL_VERSION% (%CHANNEL%) [skip ci]"
if !ERRORLEVEL! NEQ 0 (
    git diff --cached --quiet -- "%INSTALLER%\updates\latest-%CHANNEL%.json"
    if !ERRORLEVEL! EQU 0 (
        echo [INFO] El manifiesto no tuvo cambios que commitear ^(probablemente ya estaba al dia^).
    ) else (
        echo [ERROR] Fallo el commit del manifiesto de actualizacion.
        echo [ERROR] El release v%FULL_VERSION% YA fue creado en GitHub, pero el manifiesto de actualizacion NO se ha publicado todavia.
        exit /b 1
    )
)

git push origin HEAD
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo el push del manifiesto a GitHub.
    echo [ERROR] El release v%FULL_VERSION% YA fue creado en GitHub, pero los clientes NO detectaran esta actualizacion hasta que el push tenga exito.
    echo [ERROR] Ejecuta manualmente: git push origin HEAD
    exit /b 1
)
echo [OK] Manifiesto publicado en GitHub ^(latest-%CHANNEL%.json actualizado en main^).

echo.
echo [INFO] Verificando consistencia version/canal/manifest/Release/assets...
powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%\verify-manifest.ps1" -channel "%CHANNEL%"
if !ERRORLEVEL! NEQ 0 (
    echo.
    echo [ADVERTENCIA] La verificacion posterior al publish encontro inconsistencias.
    echo [ADVERTENCIA] El Release y el manifiesto YA se publicaron - esto no revierte nada.
    echo [ADVERTENCIA] Puede ser solo un retraso de propagacion de raw.githubusercontent.com.
    echo [ADVERTENCIA] Espera un minuto y vuelve a correr: publish.bat --verify %CHANNEL%
)

if exist "%INSTALLER%\output\build_version.txt" del "%INSTALLER%\output\build_version.txt"
if exist "%INSTALLER%\output\build_channel.txt" del "%INSTALLER%\output\build_channel.txt"
echo.
echo ============================================================
echo  Publish Completado Exitosamente
echo  Canal: %CHANNEL%
echo ============================================================
goto :eof

:restore_version
if exist "%INSTALLER%\version.json.bak" (
    copy /y "%INSTALLER%\version.json.bak" "%INSTALLER%\version.json" >nul
    del "%INSTALLER%\version.json.bak"
)
goto :eof
