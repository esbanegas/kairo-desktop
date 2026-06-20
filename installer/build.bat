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
if "%INSTALLER:~-1%"=="\" set "INSTALLER=%INSTALLER=%

:: 0. Leer Configuración y determinar versión SemVer resuelta (localOnly)
for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Content 'version.json' | ConvertFrom-Json).version"') do set "VERSION=%%V"
for /f "tokens=*" %%C in ('powershell -NoProfile -Command "(Get-Content 'version.json' | ConvertFrom-Json).channel"') do set "CHANNEL=%%C"

set "FULL_VERSION="
for /f "tokens=*" %%F in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%\get-version.ps1" -version "%VERSION%" -channel "%CHANNEL%" -localOnly') do set "FULL_VERSION=%%F"
if "%FULL_VERSION%"=="" (
    echo [ERROR] No se pudo determinar la version o el tag ya existe.
    exit /b 1
)

:: Hacer copia de seguridad de version.json y sobrescribir temporalmente con la versión resuelta
copy /y "%INSTALLER%\version.json" "%INSTALLER%\version.json.bak" >nul
powershell -NoProfile -Command "$json = Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json; $json.version = '%FULL_VERSION%'; $json | ConvertTo-Json -Depth 10 | Set-Content '%INSTALLER%\version.json'"

echo Version Base: %VERSION% (%CHANNEL%)
echo Version Compilada (SemVer): %FULL_VERSION%
echo.

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

echo [OK] Frontend empaquetado correctamente en: %FRONTEND%\release\win-unpacked\
echo [OK] Ejecutable verificado: !EXE_PATH!
echo.

:: ─────────────────────────────────────────
:: 2. Publish del Backend (.NET 8)
:: ─────────────────────────────────────────
echo [2/3] Publicando el backend (.NET 8)...
cd /d "%BACKEND%"

if exist "bin\Release\net8.0\publish" (
    echo [INFO] Limpiando publicacion anterior del backend...
    rmdir /s /q "bin\Release\net8.0\publish"
)

dotnet publish -c Release -o "bin\Release\net8.0\publish" --no-self-contained -r win-x64
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Fallo el publish del backend.
    call :restore_version
    exit /b 1
)
echo [OK] Backend publicado en: %BACKEND%\bin\Release\net8.0\publish\
echo.

:: ─────────────────────────────────────────
:: 3. Compilar el instalador con Inno Setup
:: ─────────────────────────────────────────
echo [3/3] Compilando instalador con Inno Setup...
cd /d "%INSTALLER%"

if exist "output" (
    echo [INFO] Limpiando carpeta de salida de instaladores anteriores...
    rmdir /s /q "output"
)

:: Ruta de ISCC
set "ISCC=C:\Users\ebanegas\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
if not exist "!ISCC!" (
    echo [ERROR] No se encontro ISCC.exe en: !ISCC!
    exit /b 1
)
echo [INFO] Usando: !ISCC!

"!ISCC!" /DAppVersion="%FULL_VERSION%" /DAppChannel="%CHANNEL%" "%INSTALLER%\enlip_setup.iss"
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo la compilacion del instalador.
    call :restore_version
    exit /b 1
)

echo.
echo ============================================================
echo  Build completado exitosamente!
echo  Instalador: %INSTALLER%\output\ENLIP_Setup_v%FULL_VERSION%.exe
echo ============================================================
call :restore_version
pause
goto :eof

:restore_version
if exist "%INSTALLER%\version.json.bak" (
    copy /y "%INSTALLER%\version.json.bak" "%INSTALLER%\version.json" >nul
    del "%INSTALLER%\version.json.bak"
)
goto :eof
