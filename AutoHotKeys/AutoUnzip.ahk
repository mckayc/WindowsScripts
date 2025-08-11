#NoEnv
#SingleInstance Force
#Persistent

; Get the Downloads folder path using environment variable
EnvGet, UserProfile, USERPROFILE
DownloadsFolder := UserProfile . "\Downloads"

; Create a file system watcher to monitor the Downloads folder
SetTimer, CheckForNewZips, 2000  ; Check every 2 seconds

; Show tray tip on startup
TrayTip, Auto-Unzip, Monitoring Downloads folder for ZIP files..., 3

CheckForNewZips:
    ; Get list of ZIP files in Downloads folder
    Loop, Files, %DownloadsFolder%\*.zip
    {
        ZipFile := A_LoopFileFullPath
        ZipName := A_LoopFileName
        ZipNameNoExt := StrReplace(ZipName, ".zip", "")
        
        ; Process each ZIP file found
        {
            ; Create extraction folder (same name as ZIP file without extension)
            ExtractFolder := DownloadsFolder . "\" . ZipNameNoExt
            
            ; Create the extraction directory if it doesn't exist
            FileCreateDir, %ExtractFolder%
            
            ; Extract the ZIP file using PowerShell (built into Windows 10/11)
            RunWait, powershell.exe -Command "Expand-Archive -Path '%ZipFile%' -DestinationPath '%ExtractFolder%' -Force", , Hide
            
            ; Check if extraction was successful
            if ErrorLevel = 0
            {
                ; Delete the original ZIP file after successful extraction
                FileDelete, %ZipFile%
                
                ; Show single completion notification
                TrayTip, Auto-Unzip, Successfully extracted and deleted %ZipName%, 3
            }
            else
            {
                ; Show error notification only if extraction failed
                TrayTip, Auto-Unzip Error, Failed to extract %ZipName%, 5
            }
        }
    }
return

; Hotkey to manually trigger check (Ctrl+Alt+U)
^!u::
    Gosub, CheckForNewZips
    TrayTip, Auto-Unzip, Manual check completed, 2
return

; Hotkey to pause/resume monitoring (Ctrl+Alt+P)
^!p::
    if (A_IsPaused)
    {
        Pause, Off
        TrayTip, Auto-Unzip, Monitoring resumed, 2
    }
    else
    {
        Pause, On
        TrayTip, Auto-Unzip, Monitoring paused, 2
    }
return

; Hotkey to exit script (Ctrl+Alt+X)
^!x::
    TrayTip, Auto-Unzip, Script terminated, 2
    Sleep, 1000
    ExitApp
return

; Clean up any leftover files if needed (reserved for future use)
CleanupMaintenance:
    ; Placeholder for any future cleanup tasks
return

; Reserved timer for future maintenance tasks
; SetTimer, CleanupMaintenance, 86400000  ; 24 hours