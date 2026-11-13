@echo off
rem ===========================================================
rem  Quick launcher for this Godot project.
rem
rem  Double-click        -> runs the game window
rem  play_game.bat -e    -> opens the editor
rem  Any extra args are forwarded to Godot, e.g.
rem  play_game.bat --headless --quit-after 120
rem ===========================================================
setlocal EnableExtensions
title Godot Game Launcher

cd /d "%~dp0"
set "PROJ=%CD%"
set "GODOT="

if not exist "%PROJ%\project.godot" goto :no_project

rem --- 1. user override: set GODOT_PATH to your own Godot.exe ---
if defined GODOT_PATH if exist "%GODOT_PATH%" set "GODOT=%GODOT_PATH%"

rem --- 2. portable engine shipped inside this project ---
if not defined GODOT if exist "%PROJ%\tools\godot\Godot_v4.7.2-stable_win64.exe" set "GODOT=%PROJ%\tools\godot\Godot_v4.7.2-stable_win64.exe"

rem --- 3. common installation folders ---
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot.exe" set "GODOT=%ProgramFiles%\Godot\Godot.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot Engine\Godot.exe" set "GODOT=%ProgramFiles%\Godot Engine\Godot.exe"
if not defined GODOT if exist "%LOCALAPPDATA%\Programs\Godot\Godot.exe" set "GODOT=%LOCALAPPDATA%\Programs\Godot\Godot.exe"
if not defined GODOT if exist "%ProgramFiles(x86)%\Godot\Godot.exe" set "GODOT=%ProgramFiles(x86)%\Godot\Godot.exe"

if not defined GODOT goto :no_engine

echo  Engine  : %GODOT%
echo  Project : %PROJ%
echo.

rem --- first run only: build import cache, otherwise global class names are missing ---
if not exist "%PROJ%\.godot\global_script_class_cache.cfg" (
    echo  [first run] importing project assets, please wait...
    "%GODOT%" --headless --path "%PROJ%" --import
    echo.
)

"%GODOT%" --path "%PROJ%" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" goto :failed
endlocal & exit /b 0


:failed
echo.
echo  ---------------------------------------------
echo   Godot exited with code %RC%.
echo   If the game window opened and closed instantly,
echo   copy the messages above when reporting the issue.
echo  ---------------------------------------------
echo.
pause
endlocal & exit /b %RC%


:no_engine
echo.
echo  [ERROR] No Godot executable found.
echo.
echo   Checked:
echo     1. %%GODOT_PATH%% environment variable
echo     2. %PROJ%\tools\godot\
echo     3. %%ProgramFiles%%\Godot\Godot.exe
echo.
echo   Fix: put Godot_v4.7.2-stable_win64.exe into
echo        %PROJ%\tools\godot\
echo   or set GODOT_PATH to your Godot.exe.
echo.
pause
endlocal & exit /b 1


:no_project
echo.
echo  [ERROR] project.godot not found next to this script.
echo   Put play_game.bat in the project root folder.
echo.
pause
endlocal & exit /b 1
