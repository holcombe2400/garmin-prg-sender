@echo off
setlocal
cd /d "%~dp0"

if "%GARMIN_SENDER_GUI_TEST%"=="1" (
    echo GUI launcher syntax OK
    exit /b 0
)

if exist ".runtime\Scripts\pythonw.exe" (
    start "" ".runtime\Scripts\pythonw.exe" "%~dp0send_prg_gui.py"
    exit /b 0
)

if exist ".runtime\Scripts\python.exe" (
    start "" ".runtime\Scripts\python.exe" "%~dp0send_prg_gui.py"
    exit /b 0
)

if exist ".venv\Scripts\pythonw.exe" (
    start "" ".venv\Scripts\pythonw.exe" "%~dp0send_prg_gui.py"
    exit /b 0
)

if exist ".venv\Scripts\python.exe" (
    start "" ".venv\Scripts\python.exe" "%~dp0send_prg_gui.py"
    exit /b 0
)

echo Python environment not found. Expected .runtime\Scripts\python.exe or .venv\Scripts\python.exe
pause
exit /b 1
