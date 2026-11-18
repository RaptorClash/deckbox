@echo off
setlocal
chcp 65001 >nul

echo ============================================================
echo  DeckBox One-Click Build (Windows + Android)
echo ============================================================
echo.

where python >nul 2>&1
if errorlevel 1 (
    echo [FEHLER] Python wurde nicht im PATH gefunden.
    goto :maybe_pause_error
)

python "%~dp0tool\build_target.py" --root "%~dp0." --build-all %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo [FEHLER] Build fehlgeschlagen ^(Exit-Code %EXIT_CODE%^).
    goto :maybe_pause_error
)

echo [OK] Alle angeforderten Builds wurden erfolgreich erstellt!

echo %cmdcmdline% | "%SystemRoot%\System32\find.exe" /i "%~0" >nul
if not errorlevel 1 pause
exit /b 0

:maybe_pause_error
echo %cmdcmdline% | "%SystemRoot%\System32\find.exe" /i "%~0" >nul
if not errorlevel 1 pause
exit /b 1
