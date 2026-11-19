@echo off
REM Double-click test wrappers - handy for testing before AutoHotkey,
REM and a Stream Deck button can also point straight at these files.
cd /d "%~dp0"
where pythonw >nul 2>nul
python play_playlist.py "5 Stars"
echo.
echo If nothing played, check play_playlist.log in this folder.
pause
