@echo off
rem ===========================================================
rem  Play the WEB build in a browser (localhost).
rem
rem  Double-click -> starts a small local server and opens the
rem  game page. Close this window to stop the server.
rem
rem  If build\web\index.html is missing, this script exports it
rem  first by calling export_web.bat.
rem ===========================================================
setlocal EnableExtensions
title Web Game Server
cd /d "%~dp0"
set "PROJ=%CD%"
set "PORT=8123"

if not exist "%PROJ%\project.godot" goto :no_project

where python >nul 2>nul
if errorlevel 1 goto :no_python

if not exist "%PROJ%\build\web\index.html" (
    echo  [build] no web build found, exporting first...
    echo.
    call "%PROJ%\export_web.bat" quiet
    if not exist "%PROJ%\build\web\index.html" goto :no_build
)

echo.
echo  Starting local server on port %PORT% ...
echo  The browser opens automatically. Close this window to stop.
echo.

python "%PROJ%\tools\serve_web.py" --open --port %PORT%
echo.
echo  Server stopped.
pause
endlocal & exit /b 0


:no_python
echo.
echo  [ERROR] Python not found in PATH.
echo.
echo  The game page needs to be served over http:// -
echo  opening index.html by double-click will NOT work.
echo.
echo  Fix: install Python from https://www.python.org/downloads/
echo       and tick "Add python.exe to PATH" during setup.
echo.
pause
endlocal & exit /b 1


:no_build
echo.
echo  [ERROR] Web export did not produce build\web\index.html.
echo   Read the messages above, then run export_web.bat by hand.
echo.
pause
endlocal & exit /b 1


:no_project
echo.
echo  [ERROR] project.godot not found next to this script.
echo   Put play_web.bat in the project root folder.
echo.
pause
endlocal & exit /b 1
