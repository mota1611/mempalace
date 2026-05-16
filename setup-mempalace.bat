@echo off
setlocal
cd /d "%~dp0"

REM Sem argumentos: abre o assistente (menus faceis em portugues).
REM Com argumentos: repassa ao PowerShell, ex.:
REM   setup-mempalace.bat -Action Update -ProjectPath "C:\meu\app"
REM   setup-mempalace.bat -Action CursorMcp

if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-mempalace.ps1" -Menu
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-mempalace.ps1" %*
)

echo.
pause
