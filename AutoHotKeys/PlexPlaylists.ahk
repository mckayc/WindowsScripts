; ============================================================
; Plex Playlists - global hotkeys (AutoHotkey v2)
; Copy to: D:\Backup Files\Git\Windows Scripts\AutoHotKeys\
; Then RUN it (double-click) - just copying it there does not
; activate it. Look for its green "H" icon in the system tray.
;
;   Alt+5        or Ctrl+Alt+5   ->  play the "5 Stars" playlist
;   Alt+4        or Ctrl+Alt+4   ->  play the "Not Rated" playlist
;   Alt+N        or Ctrl+Alt+N   ->  show a "now playing" notification
;                                    WITH album art (track, artist, album,
;                                    progress and rating) - Plexamp stays
;                                    in the background, never focused
;   Alt+9                        ->  test popup (proves this script
;                                    is running and hotkeys reach it)
;
; Both Alt and Ctrl+Alt are mapped on purpose: if Plexamp's own
; Global Keyboard Shortcuts have already grabbed Alt+4 / Alt+5
; (e.g. to rate the current track - see your 1-5 STAR buttons),
; Windows gives the key to whoever registered it first and this
; script never sees it. Ctrl+Alt+5 / Ctrl+Alt+4 will still work
; in that case, which also proves that was the problem.
;
; DIAGNOSIS LOG: every script start and every keypress is logged
; to D:\Backup Files\Git\Windows Scripts\Plex\ahk_debug.log
;   - no "script loaded" line  = this file is not running
;   - "loaded" but no "fired"  = the key never reached AutoHotkey
;                                (something else grabbed it first)
;   - "fired" but no music     = check play_playlist.log instead
; ============================================================

#SingleInstance Force

PlexScript := "D:\Backup Files\Git\Windows Scripts\Plex\play_playlist.py"
NowPlayingScript := "D:\Backup Files\Git\Windows Scripts\Plex\now_playing.py"
NowPlayingTxt := "D:\Backup Files\Git\Windows Scripts\Plex\now_playing.txt"
ToastScript := "D:\Backup Files\Git\Windows Scripts\Plex\show_toast.ps1"
DebugLog := "D:\Backup Files\Git\Windows Scripts\Plex\ahk_debug.log"

try FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " script loaded`n", DebugLog)

PlayPlaylist(KeyLabel, PlaylistName) {
    global PlexScript, DebugLog
    stamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    try FileAppend(stamp " " KeyLabel " fired -> " PlaylistName "`n", DebugLog)
    try {
        Run('pythonw "' PlexScript '" "' PlaylistName '"', , "Hide")
    } catch as err {
        try FileAppend(stamp " RUN FAILED: " err.Message "`n", DebugLog)
        MsgBox("Could not start pythonw: " err.Message, "Plex playlist hotkeys")
    }
}

ShowNowPlaying(KeyLabel) {
    global NowPlayingScript, NowPlayingTxt, ToastScript, DebugLog
    stamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    try FileAppend(stamp " " KeyLabel " fired -> now playing`n", DebugLog)
    try {
        ; 1) Python fetches the session text + album art files.
        RunWait('pythonw "' NowPlayingScript '"', , "Hide")
        ; 2) PowerShell shows a real Windows toast WITH the album art.
        toastExit := RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ToastScript '"', , "Hide")
    } catch as err {
        toastExit := 1
    }
    if (toastExit != 0) {
        ; Fallback: the plain tray tip (text only, no art) - same as before.
        try text := Trim(FileRead(NowPlayingTxt), "`r`n `t")
        catch
            text := "Could not check what is playing."
        TrayTip(text, "Now playing on Plexamp", "Mute")
        SetTimer(HideTrayTip, -6000)
    }
}

HideTrayTip() {
    TrayTip()
}

!5::PlayPlaylist("Alt+5", "5 Stars")
^!5::PlayPlaylist("Ctrl+Alt+5", "5 Stars")
!4::PlayPlaylist("Alt+4", "Not Rated")
^!4::PlayPlaylist("Ctrl+Alt+4", "Not Rated")
!n::ShowNowPlaying("Alt+N")
^!n::ShowNowPlaying("Ctrl+Alt+N")
!9::MsgBox("AutoHotkey is running and Alt+9 reached it.`nThe Plex playlist script IS loaded.", "Plex playlist hotkeys - test")
