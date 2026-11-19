@echo off
REM Client-address diagnostic - see diagnose_plex.py. Token is redacted in its output.
cd /d "%~dp0"
python diagnose_plex.py
