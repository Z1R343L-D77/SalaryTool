@echo off
rem One-click launcher for SalaryTool.
rem Double-click this file. Arguments are passed through to scripts\start.ps1:
rem   start.bat -Browser     run the browser version (no Rust needed)
rem   start.bat -Reinstall   force reinstall frontend dependencies
rem   start.bat -NoOpen      do not open a browser automatically
rem
rem Chinese UI text lives in scripts\start.ps1 (saved as UTF-8 with BOM),
rem this file is kept ASCII-only so cmd.exe never garbles it.

setlocal
rem use UTF-8 so Chinese output from PowerShell renders correctly
chcp 65001 >nul
cd /d "%~dp0"

where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1" %*
)

set "EXIT_CODE=%errorlevel%"
if not "%EXIT_CODE%"=="0" (
    echo.
    echo [Launch failed] exit code %EXIT_CODE%
    echo.
    pause
)
exit /b %EXIT_CODE%
