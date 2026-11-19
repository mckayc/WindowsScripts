@echo off
REM Test wrapper for the now-playing notification data.
REM The Alt+N hotkey shows this same text as a Windows notification.
cd /d "%~dp0"
python now_playing.py
echo.
pause
