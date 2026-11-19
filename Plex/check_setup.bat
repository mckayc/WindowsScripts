@echo off
REM One-time setup check: lists your Plex clients and playlists.
cd /d "%~dp0"
python list_plex.py
