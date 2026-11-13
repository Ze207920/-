@echo off
rem ===========================================================
rem  Export this project as a web (HTML5) game into build\web.
rem
rem  Double-click after changing the game, then run play_web.bat
rem  to try it. The whole build\web folder is what you upload to
rem  any static web host.
rem
rem  Usage: export_web.bat [quiet]
rem ===========================================================
setlocal EnableExtensions
title Web Export
cd /d "%~dp0"
set "PROJ=%CD%"
set "TPL=%APPDATA%\Godot\export_templates\4.7.2.stable"
set "GODOT="

if not exist "%PROJ%\project.godot" goto :no_project

if defined GODOT_PATH if exist "%GODOT_PATH%" set "GODOT=%GODOT_PATH%"
if not defined GODOT if exist "%PROJ%\tools\godot\Godot_v4.7.2-stable_win64_console.exe" set "GODOT=%PROJ%\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot.exe" set "GODOT=%ProgramFiles%\Godot\Godot.exe"
if not defined GODOT if exist "%LOCALAPPDATA%\Programs\Godot\Godot.exe" set "GODOT=%LOCALAPPDATA%\Programs\Godot\Godot.exe"

if not defined GODOT goto :no_engine

rem --- export templates are a separate 1 GB download; fetch only the web part ---
if not exist "%TPL%\web_nothreads_release.zip" (
    echo  [setup] web export templates missing, downloading...
    where python >nul 2>nul
    if errorlevel 1 goto :no_templates
    python "%PROJ%\tools\fetch_web_templates.py"
    if not exist "%TPL%\web_nothreads_release.zip" goto :no_templates
    echo.
)

if not exist "%PROJ%\build\web" mkdir "%PROJ%\build\web"

echo  Engine  : %GODOT%
echo  Output  : %PROJ%\build\web\index.html
echo.
"%GODOT%" --headless --path "%PROJ%" --export-release "Web" "%PROJ%\build\web\index.html"
if errorlevel 1 goto :failed

rem --- stamp the data pack, then refresh the /docs copy used by GitHub Pages ---
set "HAS_PY=0"
where python >nul 2>nul
if not errorlevel 1 set "HAS_PY=1"
if "%HAS_PY%"=="1" python "%PROJ%\tools\stamp_web.py"
if "%HAS_PY%"=="1" python "%PROJ%\tools\sync_docs.py"

if /i not "%~1"=="quiet" (
    echo.
    echo  Done. Run play_web.bat to open it in the browser.
    echo  Upload the whole build\web folder to publish it online.
    echo.
    pause
)
endlocal & exit /b 0


:failed
echo.
echo  [ERROR] Export failed. See the messages above.
echo.
pause
endlocal & exit /b 1


:no_templates
echo.
echo  [ERROR] Web export templates are not installed.
echo   Run this once:  python tools\fetch_web_templates.py
echo   (it downloads only the ~40 MB web part of the template pack)
echo.
pause
endlocal & exit /b 1


:no_engine
echo.
echo  [ERROR] No Godot executable found.
echo   Expected: %PROJ%\tools\godot\Godot_v4.7.2-stable_win64_console.exe
echo   or set GODOT_PATH to your Godot.exe.
echo.
pause
endlocal & exit /b 1


:no_project
echo.
echo  [ERROR] project.godot not found next to this script.
echo.
pause
endlocal & exit /b 1
