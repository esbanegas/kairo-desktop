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

:: 0. Leer Configuración y determinar versión SemVer resuelta (localOnly)
for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).version"') do set "VERSION=%%V"
for /f "tokens=*" %%C in ('powershell -NoProfile -Command "(Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json).channel"') do set "CHANNEL=%%C"

set "FULL_VERSION="
for /f "tokens=*" %%F in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%\get-version.ps1" -version "%VERSION%" -channel "%CHANNEL%" -localOnly') do set "FULL_VERSION=%%F"
if "%FULL_VERSION%"=="" (
    echo [ERROR] No se pudo determinar la version o el tag ya existe.
    pause
    exit /b 1
)

:: Hacer copia de seguridad de version.json y sobrescribir temporalmente con la versión resuelta
copy /y "%INSTALLER%\version.json" "%INSTALLER%\version.json.bak" >nul
powershell -NoProfile -Command "$json = Get-Content '%INSTALLER%\version.json' | ConvertFrom-Json; $json.version = '%FULL_VERSION%'; $json | ConvertTo-Json -Depth 10 | Set-Content '%INSTALLER%\version.json'"

:: Verificar que kairo-updater.exe exista en assets
if not exist "%INSTALLER%\assets\kairo-updater\kairo-updater.exe" (
    echo [INFO] kairo-updater.exe no encontrado en assets. Compilando automaticamente...
    call "%ROOT%\kairo-desktop\updater\build-updater.bat"
)

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
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo la compilacion del frontend.
    call :restore_version
    pause
    exit /b 1
)

:: Obtener nombre del producto/ejecutable desde package.json
for /f "tokens=*" %%P in ('powershell -NoProfile -Command "(Get-Content '%FRONTEND%\package.json' | ConvertFrom-Json).build.productName"') do set "PRODUCT_NAME=%%P"
if "!PRODUCT_NAME!"=="" set "PRODUCT_NAME=KAIRO POs"

set "EXE_PATH=release\win-unpacked\!PRODUCT_NAME!.exe"
set "ASAR_PATH=release\win-unpacked\resources\app.asar"

if not exist "!EXE_PATH!" (
    echo [ERROR] No se genero el ejecutable '!PRODUCT_NAME!.exe' en release\win-unpacked.
    echo Revisa el log de electron-builder para ver detalles del fallo.
    call :restore_version
    pause
    exit /b 1
)

if not exist "!ASAR_PATH!" (
    echo [ERROR] No se genero el recurso 'resources\app.asar' en release\win-unpacked.
    echo Revisa el log de electron-builder para ver detalles del fallo.
    call :restore_version
    pause
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

dotnet publish -c Release -o "bin\Release\net8.0\publish" -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo el publish del backend.
    call :restore_version
    pause
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
set "ISCC="
if defined ISCC_PATH if exist "%ISCC_PATH%" set "ISCC=%ISCC_PATH%"
if not defined ISCC (
    for /f "delims=" %%D in ('dir /b /ad-h /o-n "%ProgramFiles%\Inno Setup *" 2^>nul') do (
        if not defined ISCC if exist "%ProgramFiles%\%%D\ISCC.exe" set "ISCC=%ProgramFiles%\%%D\ISCC.exe"
    )
)
set "PF86=%ProgramFiles(x86)%"
if not defined ISCC (
    for /f "delims=" %%D in ('dir /b /ad-h /o-n "%PF86%\Inno Setup *" 2^>nul') do (
        if not defined ISCC if exist "%PF86%\%%D\ISCC.exe" set "ISCC=%PF86%\%%D\ISCC.exe"
    )
)
if not defined ISCC (
    for /f "delims=" %%D in ('dir /b /ad-h /o-n "%LocalAppData%\Programs\Inno Setup *" 2^>nul') do (
        if not defined ISCC if exist "%LocalAppData%\Programs\%%D\ISCC.exe" set "ISCC=%LocalAppData%\Programs\%%D\ISCC.exe"
    )
)
if not defined ISCC (
    for /f "tokens=*" %%I in ('where iscc.exe 2^>nul') do if not defined ISCC set "ISCC=%%I"
)
if not defined ISCC (
    echo [ERROR] No se encontro ISCC.exe. Asegurate de tener Inno Setup instalado,
    echo         o define ISCC_PATH con la ruta completa al ejecutable.
    call :restore_version
    pause
    exit /b 1
)
echo [INFO] Usando: !ISCC!

"!ISCC!" /DAppVersion="%FULL_VERSION%" /DAppChannel="%CHANNEL%" "%INSTALLER%\enlip_setup.iss"
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Fallo la compilacion del instalador.
    call :restore_version
    pause
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
