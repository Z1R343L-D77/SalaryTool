@echo off
rem One-click iOS UI preview for Windows.
rem
rem Opens a WebKit window sized like an iPhone, with hot reload.
rem Arguments are passed through to tools\preview.mjs:
rem   preview.bat --device iphone15   switch device
rem   preview.bat --no-notch          drop safe-area simulation
rem   preview.bat --build             serve the production build
rem
rem Chinese UI text is printed by the Node script (UTF-8) instead,
rem so this file stays ASCII-only and cmd.exe never garbles it.

setlocal
chcp 65001 >nul
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
    echo.
    echo   Node.js not found. Install it first: https://nodejs.org/
    echo.
    pause
    exit /b 1
)

if not exist "node_modules\playwright" (
    echo   First run: installing preview engine...
    call npm install
    if errorlevel 1 goto :failed
    call npx playwright install webkit
    if errorlevel 1 goto :failed
)

echo.
node tools\preview.mjs %*
if errorlevel 1 goto :failed
exit /b 0

:failed
echo.
echo   Preview failed. See the messages above.
echo.
pause
exit /b 1
