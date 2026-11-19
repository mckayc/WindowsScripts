; ============================================================
; Plex Playlists - global hotkeys (AutoHotkey v1 - use this
; file instead of PlexPlaylists.ahk if your other scripts are v1)
; Copy to: D:\Backup Files\Git\Windows Scripts\AutoHotKeys\
;
;   Alt+5  ->  play the "5 Stars" playlist in Plexamp
;   Alt+4  ->  play the "Not Rated" playlist in Plexamp
;
; If a key does nothing, check play_playlist.log in the Plex folder.
; See the v2 file for the Alt+4 / Alt+5 rating-clash warning.
; ============================================================

#SingleInstance force

PlexScript := "D:\Backup Files\Git\Windows Scripts\Plex\play_playlist.py"

!5::
Run, pythonw "%PlexScript%" "5 Stars", , Hide
return

!4::
Run, pythonw "%PlexScript%" "Not Rated", , Hide
return
