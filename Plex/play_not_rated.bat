@echo off
REM Double-click test wrappers - handy for testing before AutoHotkey,
REM and a Stream Deck button can also point straight at these files.
cd /d "%~dp0"
python play_playlist.py "Not Rated"
echo.
echo If nothing played, check play_playlist.log in this folder.
pause
