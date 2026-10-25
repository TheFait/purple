@echo off
rem Starts the dedicated server and two game windows so you can try online play by hand.
rem In the first window press PLAY ONLINE, type a name, HOST A GAME, CREATE TABLE and read the
rem invite code. In the second press PLAY ONLINE, type another name, JOIN WITH CODE and enter it.
rem (The server address already says 127.0.0.1.) The host presses START GAME once both are in.
rem
rem Godot is looked for in GODOT_DIR. Set that variable first to use a different install:
rem     set GODOT_DIR=C:\Tools\Godot_v4.6
rem     tools\run_online_test.bat
rem Close the server window to stop the server (closing the clients does not).

setlocal
if not defined GODOT_DIR set "GODOT_DIR=F:\Development\Godot\Godot_v4.6"
set "GODOT=%GODOT_DIR%\Godot_v4.6-stable_win64.exe"
set "GODOT_CONSOLE=%GODOT_DIR%\Godot_v4.6-stable_win64_console.exe"
for %%I in ("%~dp0..") do set "PROJECT=%%~fI"

rem Window size and where the two clients sit on screen (the game is 720x1280, scaled down to fit).
set "SIZE=450x800"
set "POS1=20,40"
set "POS2=490,40"

if not exist "%GODOT%" (
	echo Could not find %GODOT%
	echo Set GODOT_DIR to the folder that holds Godot_v4.6-stable_win64.exe
	pause
	exit /b 1
)
if not exist "%GODOT_CONSOLE%" (
	echo Could not find %GODOT_CONSOLE%
	pause
	exit /b 1
)

echo Starting the server...
start "Purple server" "%GODOT_CONSOLE%" --headless --path "%PROJECT%" server/server.tscn

rem Give the server a moment to start listening before the clients look for it.
timeout /t 3 /nobreak >nul

echo Starting client 1 and client 2...
start "Purple client 1" "%GODOT%" --path "%PROJECT%" --resolution %SIZE% --position %POS1%
start "Purple client 2" "%GODOT%" --path "%PROJECT%" --resolution %SIZE% --position %POS2%

endlocal
