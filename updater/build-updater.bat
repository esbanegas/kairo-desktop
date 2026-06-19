@echo off
:: ============================================================
:: Build kairo-updater.exe (self-contained, single-file, win-x64)
:: Output: updater\KairoUpdater\bin\publish\kairo-updater.exe
:: ============================================================
setlocal

set "UPDATER_DIR=%~dp0KairoUpdater"
set "PUBLISH_DIR=%UPDATER_DIR%\bin\publish"
set "INSTALLER_ASSETS=%~dp0..\installer\assets\kairo-updater"

echo [BUILD] Compilando kairo-updater.exe...
dotnet publish "%UPDATER_DIR%\KairoUpdater.csproj" ^
  -c Release ^
  -r win-x64 ^
  --self-contained true ^
  -p:PublishSingleFile=true ^
  -o "%PUBLISH_DIR%"

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build fallido.
    exit /b 1
)

echo [OK] Binario generado: %PUBLISH_DIR%\kairo-updater.exe

:: Copiar al directorio de assets del instalador
if not exist "%INSTALLER_ASSETS%" mkdir "%INSTALLER_ASSETS%"
copy /y "%PUBLISH_DIR%\kairo-updater.exe" "%INSTALLER_ASSETS%\kairo-updater.exe" >nul
echo [OK] Copiado a: %INSTALLER_ASSETS%\kairo-updater.exe

echo.
echo Listo. Ahora puedes correr build.bat para incluirlo en el instalador.
