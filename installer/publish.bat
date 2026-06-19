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

:: Reemplazar variables en GITHUB_BASE_URL
set "BASE_URL=!GITHUB_BASE_URL:{repo_owner}=%REPO_OWNER%!"
set "BASE_URL=!BASE_URL:{repo_name}=%REPO_NAME%!"
set "BASE_URL=!BASE_URL:{version}=%VERSION%!"

echo Version: %VERSION% (%CHANNEL%)
echo Base URL: %BASE_URL%

set "OUTPUT=%INSTALLER%\output\updates\%VERSION%"
if not exist "%OUTPUT%" mkdir "%OUTPUT%"

:: 2. Compilar Frontend (Electron) y Zip
echo [1/4] Construyendo frontend (Vite/Electron)...
cd /d "%FRONTEND%"
if exist "release" rmdir /s /q "release"
call pnpm run build:electron
if not exist "release\win-unpacked\" (
    echo [ERROR] No se genero release\win-unpacked
    exit /b 1
)

set "FRONTEND_ZIP=%OUTPUT%\frontend.zip"
if exist "%FRONTEND_ZIP%" del "%FRONTEND_ZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%FRONTEND%\dist\*' -DestinationPath '%FRONTEND_ZIP%' -Force"
echo [OK] frontend.zip

:: 3. Compilar Backend y Zip
echo [2/4] Construyendo backend (.NET)...
cd /d "%BACKEND%"
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
"!ISCC!" /DAppVersion="%VERSION%" "%INSTALLER%\enlip_setup.iss"
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo Inno Setup.
    exit /b 1
)
set "INSTALLER_EXE=%INSTALLER%\output\ENLIP_Setup_v%VERSION%.exe"
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
  echo     "version": "%VERSION%",
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

echo.
echo ============================================================
echo  Build Completado Exitosamente
echo  Resultados en: %OUTPUT%
echo ============================================================
goto :eof


:publish
echo ============================================================
echo  FASE PUBLISH (--publish)
echo ============================================================

for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).version"') do set "VERSION=%%V"
for /f "tokens=*" %%C in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).channel"') do set "CHANNEL=%%C"
set "OUTPUT=%INSTALLER%\output\updates\%VERSION%"

if not exist "%OUTPUT%\latest-%CHANNEL%.json" (
    echo [ERROR] No existe el build local. Ejecuta --build-only primero.
    exit /b 1
)

echo [1/2] Verificando GitHub CLI...
gh --version >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] GitHub CLI [gh] no esta instalado o autenticado.
    exit /b 1
)

echo [2/2] Publicando Release v%VERSION% en GitHub...
cd /d "%INSTALLER%\.."
git tag -a v%VERSION% -m "Release v%VERSION%"
git push origin v%VERSION%

gh release create v%VERSION% ^
    "%OUTPUT%\KairoSetup.exe" ^
    "%OUTPUT%\frontend.zip" ^
    "%OUTPUT%\backend.zip" ^
    "%OUTPUT%\latest-%CHANNEL%.json" ^
    --title "Kairo POS v%VERSION%" ^
    --notes "Nueva actualizacion de Kairo POS v%VERSION%"

echo.
echo ============================================================
echo  Publish Completado Exitosamente
echo ============================================================
goto :eof
