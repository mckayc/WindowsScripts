#NoEnv
#SingleInstance Force
#UseHook On

; ============================================================================== 
; YoloCam S3 direct ePTZ + YoloLiv S7 CamParam controller
; S3 cameras use the reverse-engineered TCP control protocol directly.
; S7 continues to use CamParam.exe.
; ============================================================================== 

; ------------------------------------------------------------------------------
; USER VARIABLES & LIMITS
; ------------------------------------------------------------------------------
ExeName      := "yolocam-s3-zoom-multi.exe"
ExeURL       := "https://github.com/scottgarner/CamParam/releases/download/v0.0.2/CamParam.exe"
CamParamName := "CamParam.exe"
LogFolder    := "logs"
LogFileName  := "webcamzoom.log"
ZoomStepPct  := 10

; S3 native zoom range is 1.0x - 4.0x.
; The user-facing scale remains 0% - 100%.
S3_MinZoom := 1.0
S3_MaxZoom := 4.0

; --- Camera 1: Talking Head ---
global C1_Name := "Talking Head", C1_IP := "192.168.124.10", C1_Pct := 0

; --- Camera 2: Overhead ---
global C2_Name := "Overhead", C2_IP := "192.168.123.10", C2_Pct := 0

; --- Camera 3: Side ---
global C3_Name := "Side", C3_IP := "192.168.127.10", C3_Pct := 0

; --- Camera 4: YoloLiv S7 (CamParam) ---
global C4_Name := "Yololiv S7", C4_SN := "Y-CAM-26020026", C4_Min := 50, C4_Max := 98, C4_ID := -1, C4_Pct := 0

global LogPath := A_ScriptDir . "\" . LogFolder . "\" . LogFileName

; ============================================================================== 
; INITIALIZATION
; ============================================================================== 
SetWorkingDir %A_ScriptDir%
if !FileExist(LogFolder)
    FileCreateDir, %LogFolder%

LogWrite("--- Script Started ---")

if !FileExist(ExeName) {
    MsgBox, 16, YoloCam Zoom, % "Missing " . ExeName . ".`nPlace it in the same folder as this AHK script."
    ExitApp
}

if !FileExist(CamParamName) {
    LogWrite("CamParam.exe missing. Downloading...")
    UrlDownloadToFile, %ExeURL%, %CamParamName%
    if !FileExist(CamParamName) {
        MsgBox, 16, YoloCam Zoom, CamParam.exe could not be downloaded. The S3 controls will still work, but the S7 will not.
    }
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
^#w:: AdjustAndApply(2, -ZoomStepPct)

; Cam 3 (Side)
^#3:: AdjustAndApply(3, ZoomStepPct)
^#e:: AdjustAndApply(3, -ZoomStepPct)

; Cam 4 (Yololiv S7)
^#4:: AdjustAndApply(4, ZoomStepPct)
^#d:: AdjustAndApply(4, -ZoomStepPct)

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

    ; S3 cameras: read their actual native ePTZ zoom.
    Loop, 3 {
        SyncS3Cam(A_Index)
    }

    ; S7: discover CamParam device ID and read its hardware zoom.
    if FileExist(CamParamName)
        InitializeS7()
}

InitializeS7() {
    global
    TempFile := A_ScriptDir . "\temp_scan_s7.txt"
    RunWait, %ComSpec% /c ""%A_ScriptDir%\%CamParamName%" > "%TempFile%" 2>&1", , Hide
    FileRead, OutputVar, %TempFile%

    C4_ID := -1
    Loop, parse, OutputVar, `n, `r
    {
        if InStr(A_LoopField, C4_SN) {
            RegExMatch(A_LoopField, "\d+", Match)
            C4_ID := Match
            SyncS7()
            break
        }
    }
    FileDelete, %TempFile%
}

SyncS3Cam(n) {
    global
    thisIP := C%n%_IP
    TempFile := A_ScriptDir . "\temp_sync_s3_" . n . ".txt"

    FullExePath := A_ScriptDir . "\" . ExeName
    RunWait, %ComSpec% /c ""%FullExePath%" %thisIP% get > "%TempFile%" 2>&1", , Hide
    FileRead, OutputVar, %TempFile%
    FileDelete, %TempFile%

    ; Successful output: 1.00 0.500 0.500
    RegExMatch(OutputVar, "m)^([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)", M)
    if (M1 != "") {
        factor := M1 + 0.0
        pct := Round(((factor - S3_MinZoom) / (S3_MaxZoom - S3_MinZoom)) * 100)
        if (pct < 0)
            pct := 0
        if (pct > 100)
            pct := 100
        C%n%_Pct := pct
        LogWrite("Synced " . C%n%_Name . " to " . factor . "x (" . pct . "%)")
    } else {
        LogWrite("Could not sync " . C%n%_Name . " (" . thisIP . "): " . OutputVar)
    }
}

SyncS7() {
    global
    thisID := C4_ID
    if (thisID = -1)
        return

    TempFile := A_ScriptDir . "\temp_sync_s7.txt"
    RunWait, %ComSpec% /c ""%A_ScriptDir%\%CamParamName%" device %thisID% > "%TempFile%" 2>&1", , Hide
    FileRead, DeviceInfo, %TempFile%
    FileDelete, %TempFile%

    Loop, parse, DeviceInfo, `n, `r
    {
        if (InStr(A_LoopField, "zoom", false)) {
            RegExMatch(A_LoopField, "\d+", HWValue)
            C4_Pct := Round(((HWValue - C4_Min) / (C4_Max - C4_Min)) * 100)
            if (C4_Pct < 0)
                C4_Pct := 0
            if (C4_Pct > 100)
                C4_Pct := 100
            LogWrite("Synced " . C4_Name . " to " . HWValue . " (" . C4_Pct . "%)")
            break
        }
    }
}

MultiAdjust(Step) {
    Loop, 4
        AdjustAndApply(A_Index, Step)
}

AdjustAndApply(n, Step) {
    global

    if (n <= 3) {
        AdjustS3(n, Step)
        return
    }

    ; S7 via CamParam
    thisID := C4_ID
    if (thisID = -1) {
        InitializeS7()
        thisID := C4_ID
        if (thisID = -1)
            return
    }

    C4_Pct += Step
    if (C4_Pct > 100)
        C4_Pct := 100
    if (C4_Pct < 0)
        C4_Pct := 0

    HWVal := Round(C4_Min + (C4_Pct / 100) * (C4_Max - C4_Min))
    FullExePath := A_ScriptDir . "\" . CamParamName
    RunCmd := """" . FullExePath . """ device " . thisID . " zoom " . HWVal
    Run, %RunCmd%, , Hide

    ToolTip, % C4_Name . "`nZoom: " . C4_Pct . "% (Level: " . HWVal . ")", 700, 20, 4
    SetTimer, RemoveToolTips, -2500
    LogWrite("Adjusted " . C4_Name . " to " . C4_Pct . "% (" . HWVal . ")")
}

AdjustS3(n, Step) {
    global
    thisIP := C%n%_IP
    thisName := C%n%_Name

    C%n%_Pct += Step
    if (C%n%_Pct > 100)
        C%n%_Pct := 100
    if (C%n%_Pct < 0)
        C%n%_Pct := 0

    thisPct := C%n%_Pct
    factor := S3_MinZoom + (thisPct / 100.0) * (S3_MaxZoom - S3_MinZoom)
    factor := Round(factor, 2)

    FullExePath := A_ScriptDir . "\" . ExeName
    RunCmd := """" . FullExePath . """ " . thisIP . " set " . factor
    Run, %RunCmd%, , Hide

    ToolTip, % thisName . "`nZoom: " . thisPct . "% (" . factor . "x)", (n*220)-180, 20, n
    SetTimer, RemoveToolTips, -2500
    LogWrite("Adjusted " . thisName . " to " . thisPct . "% (" . factor . "x)")
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
    ToolTip, , , , 4
return
