@echo off
setlocal EnableDelayedExpansion

echo ============================================================
echo  ENLIP POs - Build Completo para Instalador
echo ============================================================
echo.

set "ROOT=%~dp0..\.."
set "FRONTEND=%ROOT%\acg-web"
set "BACKEND=%ROOT%\enlip-services\ENLIPWebApi"
set "INSTALLER=%~dp0"
if "%INSTALLER:~-1%"=="\" set "INSTALLER=%INSTALLER:~0,-1%"

:: ─────────────────────────────────────────
:: 1. Build + Package del Frontend (Electron)
:: ─────────────────────────────────────────
echo [1/3] Construyendo el frontend (Vite + Electron)...
cd /d "%FRONTEND%"

if exist "release" (
    echo [INFO] Limpiando release anterior...
    rmdir /s /q "release"
)

call pnpm run build:electron
:: electron-builder puede fallar en winCodeSign (symlinks) pero el exe ya fue creado.
:: Verificamos que win-unpacked exista en lugar de revisar ERRORLEVEL.
if not exist "release\win-unpacked\" (
    echo [ERROR] No se genero release\win-unpacked. Revisa el log de electron-builder.
    exit /b 1
)
echo [OK] Frontend empaquetado en: %FRONTEND%\release\win-unpacked\
echo.

:: ─────────────────────────────────────────
:: 2. Publish del Backend (.NET 8)
:: ─────────────────────────────────────────
echo [2/3] Publicando el backend (.NET 8)...
cd /d "%BACKEND%"

dotnet publish -c Release -o "bin\Release\net8.0\publish" --no-self-contained -r win-x64
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Fallo el publish del backend.
    exit /b 1
)
echo [OK] Backend publicado en: %BACKEND%\bin\Release\net8.0\publish\
echo.

:: ─────────────────────────────────────────
:: 3. Compilar el instalador con Inno Setup
:: ─────────────────────────────────────────
echo [3/3] Compilando instalador con Inno Setup...
cd /d "%INSTALLER%"

:: Ruta de ISCC
set "ISCC=C:\Users\ebanegas\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
if not exist "!ISCC!" (
    echo [ERROR] No se encontro ISCC.exe en: !ISCC!
    exit /b 1
)
echo [INFO] Usando: !ISCC!

:: Obtener versión desde version.json
for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Content 'version.json' | ConvertFrom-Json).app"') do set "APP_VERSION=%%V"
if "%APP_VERSION%"=="" set "APP_VERSION=1.0.0"
echo [INFO] Detectada version v%APP_VERSION% desde version.json

"!ISCC!" /DAppVersion="%APP_VERSION%" "%INSTALLER%\enlip_setup.iss"
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo la compilacion del instalador.
    exit /b 1
)

echo.
echo ============================================================
echo  Build completado exitosamente!
echo  Instalador: %INSTALLER%\output\ENLIP_Setup_v%APP_VERSION%.exe
echo ============================================================
pause
