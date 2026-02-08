#NoEnv
#SingleInstance Force
#UseHook On

; ==============================================================================
; USER VARIABLES & LIMITS
; ==============================================================================
ExeURL       := "https://github.com/scottgarner/CamParam/releases/download/v0.0.2/CamParam.exe"
ExeName      := "CamParam.exe"
LogFolder    := "logs"
LogFileName  := "webcamzoom.log"
ZoomStepPct  := 10

; --- Camera 1: Talking Head ---
global C1_Name := "Talking Head", C1_SN := "S3-25350079", C1_Min := 50, C1_Max := 98, C1_ID := -1, C1_Pct := 0

; --- Camera 2: Overhead ---
global C2_Name := "Overhead",     C2_SN := "S3-25400090", C2_Min := 50, C2_Max := 98, C2_ID := -1, C2_Pct := 0

; --- Camera 3: Side ---
global C3_Name := "Side",         C3_SN := "S3-25400004", C3_Min := 50, C3_Max := 98, C3_ID := -1, C3_Pct := 0

global LogPath := A_ScriptDir . "\" . LogFolder . "\" . LogFileName

; ==============================================================================
; INITIALIZATION
; ==============================================================================
SetWorkingDir %A_ScriptDir%
if !FileExist(LogFolder)
    FileCreateDir, %LogFolder%

LogWrite("--- Script Started ---")

if !FileExist(ExeName) {
    LogWrite("EXE missing. Downloading...")
    UrlDownloadToFile, %ExeURL%, %ExeName%
}

InitializeCameras()
return 

; ==============================================================================
; HOTKEYS
; ==============================================================================

; Global Zoom
^#=:: MultiAdjust(ZoomStepPct)
^#-:: MultiAdjust(-ZoomStepPct)

; Cam 1 (Talking Head)
^#1:: AdjustAndApply(1, ZoomStepPct)
^#q:: AdjustAndApply(1, -ZoomStepPct)

; Cam 2 (Overhead)
^#2:: AdjustAndApply(2, ZoomStepPct)
^#w:: AdjustAndApply(2, -ZoomStepPct) ; Use 'S' to avoid Windows 'W' conflict

; Cam 3 (Side)
^#3:: AdjustAndApply(3, ZoomStepPct)
^#e:: AdjustAndApply(3, -ZoomStepPct)

; Re-sync
^#r:: 
    InitializeCameras()
    TrayTip, WebcamZoom, All Cameras Re-Synced, 2, 1
return

; ==============================================================================
; FUNCTIONS
; ==============================================================================

InitializeCameras() {
    global
    TempFile := A_ScriptDir . "\temp_scan.txt"
    RunWait, %ComSpec% /c ""%A_ScriptDir%\%ExeName%" > "%TempFile%" 2>&1", , Hide
    FileRead, OutputVar, %TempFile%

    Loop, 3 {
        n := A_Index
        sn := C%n%_SN
        C%n%_ID := -1 
        Loop, parse, OutputVar, `n, `r
        {
            if InStr(A_LoopField, sn) {
                RegExMatch(A_LoopField, "\d+", Match)
                C%n%_ID := Match
                SyncCam(n)
                break
            }
        }
    }
    FileDelete, %TempFile%
}

MultiAdjust(Step) {
    Loop, 3
        AdjustAndApply(A_Index, Step)
}

AdjustAndApply(n, Step) {
    global
    thisID := C%n%_ID
    
    if (thisID = -1) {
        InitializeCameras()
        thisID := C%n%_ID
        if (thisID = -1) 
            return
    }

    C%n%_Pct += Step
    if (C%n%_Pct > 100) 
        C%n%_Pct := 100
    if (C%n%_Pct < 0) 
        C%n%_Pct := 0
    
    thisMin  := C%n%_Min
    thisMax  := C%n%_Max
    thisName := C%n%_Name
    thisPct  := C%n%_Pct
    
    HWVal    := Round(thisMin + (thisPct / 100) * (thisMax - thisMin))
    
    FullExePath := A_ScriptDir . "\" . ExeName
    RunCmd := """" . FullExePath . """ device " . thisID . " zoom " . HWVal
    Run, %RunCmd%, , Hide
    
    ; ToolTip: Name, Percentage, and exact Hardware level
    ToolTip, % thisName . "`nZoom: " . thisPct . "% (Level: " . HWVal . ")", (n*220)-180, 20, n
    SetTimer, RemoveToolTips, -2500
    LogWrite("Adjusted " . thisName . " to " . thisPct . "% (" . HWVal . ")")
}

SyncCam(n) {
    global
    thisID := C%n%_ID, thisMin := C%n%_Min, thisMax := C%n%_Max
    if (thisID = -1) 
        return
        
    TempFile := A_ScriptDir . "\temp_sync_" . n . ".txt"
    RunWait, %ComSpec% /c ""%A_ScriptDir%\%ExeName%" device %thisID% > "%TempFile%" 2>&1", , Hide
    FileRead, DeviceInfo, %TempFile%
    FileDelete, %TempFile%
    
    Loop, parse, DeviceInfo, `n, `r
    {
        if (InStr(A_LoopField, "zoom", false)) {
            RegExMatch(A_LoopField, "\d+", HWValue)
            C%n%_Pct := Round(((HWValue - thisMin) / (thisMax - thisMin)) * 100)
            break
        }
    }
}

LogWrite(Text) {
    global LogPath
    FormatTime, TimeString, , yyyy-MM-dd HH:mm:ss
    FileAppend, %TimeString% - %Text%`r`n, %LogPath%
}

RemoveToolTips:
    ToolTip, , , , 1
    ToolTip, , , , 2
    ToolTip, , , , 3
return