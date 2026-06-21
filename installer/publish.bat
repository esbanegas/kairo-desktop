@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: KAIRO POS — Publish Pipeline (Build & Deploy)
:: ============================================================

set "ROOT=%~dp0..\.."
set "FRONTEND=%ROOT%\acg-web"
set "BACKEND=%ROOT%\enlip-services\ENLIPWebApi"
set "INSTALLER=%~dp0"
if "%INSTALLER:~-1%"=="\" set "INSTALLER=%INSTALLER:~0,-1%"

if "%~1"=="--build-only" goto :build
if "%~1"=="--publish" goto :publish

echo Uso: publish.bat --build-only   [Solo empaqueta y genera manifiesto]
echo      publish.bat --publish      [Crea release en GitHub y sube assets]
exit /b 1

:build
echo ============================================================
echo  FASE BUILD (--build-only)
echo ============================================================

:: 1. Leer Configuración
for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).version"') do set "VERSION=%%V"
for /f "tokens=*" %%C in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).channel"') do set "CHANNEL=%%C"
for /f "tokens=*" %%O in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\build.config.json' | ConvertFrom-Json).repo_owner"') do set "REPO_OWNER=%%O"
for /f "tokens=*" %%N in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\build.config.json' | ConvertFrom-Json).repo_name"') do set "REPO_NAME=%%N"
for /f "tokens=*" %%U in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\build.config.json' | ConvertFrom-Json).github_base_url"') do set "GITHUB_BASE_URL=%%U"
for /f "tokens=*" %%D in ('powershell -NoProfile -Command "[DateTime]::UtcNow.ToString(\"yyyy-MM-ddTHH:mm:ssZ\")"') do set "BUILD_DATE=%%D"

:: Obtener la versión SemVer resuelta
set "FULL_VERSION="
for /f "tokens=*" %%F in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%\get-version.ps1" -version "%VERSION%" -channel "%CHANNEL%"') do set "FULL_VERSION=%%F"
if "%FULL_VERSION%"=="" (
    echo [ERROR] No se pudo determinar la version o el tag ya existe.
    exit /b 1
)

:: Hacer copia de seguridad de version.json y sobrescribir temporalmente con la versión resuelta
copy /y "%INSTALLER%\version.json" "%INSTALLER%\version.json.bak" >nul
powershell -NoProfile -Command "$json = Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json; $json.version = '%FULL_VERSION%'; $json | ConvertTo-Json -Depth 10 | Set-Content '%INSTALLER%\version.json'"

:: Reemplazar variables en GITHUB_BASE_URL usando FULL_VERSION
set "BASE_URL=!GITHUB_BASE_URL:{repo_owner}=%REPO_OWNER%!"
set "BASE_URL=!BASE_URL:{repo_name}=%REPO_NAME%!"
set "BASE_URL=!BASE_URL:{version}=%FULL_VERSION%!"

echo Version Base: %VERSION% (%CHANNEL%)
echo Version Compilada (SemVer): %FULL_VERSION%
echo Base URL: %BASE_URL%

if exist "%INSTALLER%\output" (
    echo [INFO] Limpiando carpeta de salida anterior...
    rmdir /s /q "%INSTALLER%\output"
)

set "OUTPUT=%INSTALLER%\output\updates\%FULL_VERSION%"
if not exist "%OUTPUT%" mkdir "%OUTPUT%"

:: 2. Compilar Frontend (Electron) y Zip
echo [1/4] Construyendo frontend (Vite/Electron)...
cd /d "%FRONTEND%"
if exist "release" rmdir /s /q "release"
call pnpm run build:electron

:: Obtener nombre del producto/ejecutable desde package.json
for /f "tokens=*" %%P in ('powershell -NoProfile -Command "(Get-Content 'package.json' | ConvertFrom-Json).build.productName"') do set "PRODUCT_NAME=%%P"
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
:: Comprimir app.asar en lugar de dist/*
powershell -NoProfile -Command "Compress-Archive -Path '%ASAR_PATH%' -DestinationPath '%FRONTEND_ZIP%' -Force"
echo [OK] frontend.zip (empaquetado con app.asar)


:: 3. Compilar Backend y Zip
echo [2/4] Construyendo backend (.NET)...
cd /d "%BACKEND%"

if exist "bin\Release\net8.0\publish" (
    echo [INFO] Limpiando publicacion anterior del backend...
    rmdir /s /q "bin\Release\net8.0\publish"
)

dotnet publish -c Release -o "bin\Release\net8.0\publish" --no-self-contained -r win-x64
set "BACKEND_ZIP=%OUTPUT%\backend.zip"
set "BACKEND_PUBLISH=%BACKEND%\bin\Release\net8.0\publish"
if exist "%BACKEND_ZIP%" del "%BACKEND_ZIP%"
powershell -NoProfile -Command "Get-ChildItem '%BACKEND_PUBLISH%' -Exclude 'appsettings*.json','web.config' -Recurse | Compress-Archive -DestinationPath '%BACKEND_ZIP%' -Force"
echo [OK] backend.zip

:: 4. Compilar Instalador
echo [3/4] Compilando instalador (Inno Setup)...
cd /d "%INSTALLER%"

set "ISCC=C:\Users\ebanegas\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
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

:: 5. Calcular Hashes SHA256
echo [4/4] Calculando Hashes...
for /f "tokens=1" %%H in ('powershell -NoProfile -Command "(Get-FileHash '%FRONTEND_ZIP%' -Algorithm SHA256).Hash.ToLower()"') do set "FRONTEND_SHA=%%H"
for /f "tokens=1" %%H in ('powershell -NoProfile -Command "(Get-FileHash '%BACKEND_ZIP%' -Algorithm SHA256).Hash.ToLower()"') do set "BACKEND_SHA=%%H"
for /f "tokens=1" %%H in ('powershell -NoProfile -Command "(Get-FileHash '%TARGET_INSTALLER_EXE%' -Algorithm SHA256).Hash.ToLower()"') do set "INSTALLER_SHA=%%H"

:: 6. Generar latest-stable.json (KAIRO UPDATE MANIFEST V1.0)
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
echo %FULL_VERSION%> "%INSTALLER%\output\build_version.txt"
echo.
echo ============================================================
echo  Build Completado Exitosamente
echo  Resultados en: %OUTPUT%
echo ============================================================
call :restore_version
goto :eof


:publish
echo ============================================================
echo  FASE PUBLISH (--publish)
echo ============================================================

for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).version"') do set "VERSION=%%V"
for /f "tokens=*" %%C in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).channel"') do set "CHANNEL=%%C"

set "FULL_VERSION="
if exist "%INSTALLER%\output\build_version.txt" (
    for /f "usebackq tokens=*" %%F in ("%INSTALLER%\output\build_version.txt") do set "FULL_VERSION=%%F"
    if defined FULL_VERSION set "FULL_VERSION=!FULL_VERSION: =!"
    echo [INFO] Detectada version compilada previa: !FULL_VERSION!
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
    echo [ERROR] No existe el build local en '%OUTPUT%'. Ejecuta --build-only primero.
    exit /b 1
)

echo [1/2] Verificando GitHub CLI...
gh --version >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] GitHub CLI [gh] no esta instalado o autenticado.
    exit /b 1
)

echo [2/2] Publicando Release v%FULL_VERSION% en GitHub...
cd /d "%INSTALLER%\.."

git rev-parse "v%FULL_VERSION%" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    git tag -a v%FULL_VERSION% -m "Release v%FULL_VERSION%"
) else (
    echo [INFO] El tag v%FULL_VERSION% ya existe localmente. Omitiendo creacion...
)
git push origin v%FULL_VERSION%

set "PRERELEASE_FLAG="
if "%CHANNEL%"=="alpha" set "PRERELEASE_FLAG=--prerelease"
if "%CHANNEL%"=="beta" set "PRERELEASE_FLAG=--prerelease"

gh release create v%FULL_VERSION% ^
    "%OUTPUT%\KairoSetup.exe" ^
    "%OUTPUT%\frontend.zip" ^
    "%OUTPUT%\backend.zip" ^
    "%OUTPUT%\latest-%CHANNEL%.json" ^
    --title "Kairo POS v%FULL_VERSION%" ^
    --notes "Nueva actualizacion de Kairo POS v%FULL_VERSION%" ^
    !PRERELEASE_FLAG!

if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo la creacion de la release en GitHub.
    exit /b 1
)

echo [3/3] Publicando manifiesto de actualizacion en git...
if not exist "%INSTALLER%\updates" mkdir "%INSTALLER%\updates"
copy /y "%OUTPUT%\latest-%CHANNEL%.json" "%INSTALLER%\updates\latest-%CHANNEL%.json" >nul

git add "%INSTALLER%\updates\latest-%CHANNEL%.json"
git commit -m "Update manifest for v%FULL_VERSION% [skip ci]"
git push origin HEAD

if exist "%INSTALLER%\output\build_version.txt" del "%INSTALLER%\output\build_version.txt"
echo.
echo ============================================================
echo  Publish Completado Exitosamente
echo ============================================================
goto :eof

:restore_version
if exist "%INSTALLER%\version.json.bak" (
    copy /y "%INSTALLER%\version.json.bak" "%INSTALLER%\version.json" >nul
    del "%INSTALLER%\version.json.bak"
)
goto :eof
