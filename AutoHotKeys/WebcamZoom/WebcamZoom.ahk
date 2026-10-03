#NoEnv
#SingleInstance Force
#UseHook On
SendMode Input
SetWorkingDir %A_ScriptDir%

; ============================================================
; YoloCam S3 + Yololiv S7 Zoom Controller
; AutoHotkey v1.1.36.02 Unicode 64-bit
; ============================================================

global ZoomStepPct := 5

; ============================================================
; S3 SETTINGS
; ============================================================

global S3Exe := A_ScriptDir . "\yolocam-s3-zoom\yolocam-s3-zoom-multi-win64.exe"

global S3IP1 := "192.168.127.10"
global S3IP2 := "192.168.124.10"
global S3IP3 := "192.168.123.10"

global S3Zoom1 := 0
global S3Zoom2 := 0
global S3Zoom3 := 0

; ============================================================
; S7 SETTINGS
; ============================================================

global S7Serial := "Y-CAM-26020026"
global S7Min := 50
global S7Max := 98
global S7ID := -1
global S7Zoom := 50

global CamParamExe := A_ScriptDir . "\CamParam.exe"

; S7 network control
global S7FocusIP := "192.168.127.10"
global S7FocusPort := 12345

; ============================================================
; LOGGING
; ============================================================

global LogFolder := A_ScriptDir . "\logs"
global LogFileName := "webcamzoom.log"


; ============================================================
; STARTUP
; ============================================================

if !FileExist(LogFolder)
    FileCreateDir, %LogFolder%

Log("========================================")
Log("Webcam Zoom Controller starting")
Log("S3 EXE: " . S3Exe)
Log("S3 IP1: " . S3IP1)
Log("S3 IP2: " . S3IP2)
Log("S3 IP3: " . S3IP3)
Log("S7 Serial: " . S7Serial)
Log("S7 Focus IP: " . S7FocusIP)
Log("S7 Focus Port: " . S7FocusPort)
Log("========================================")

InitializeCameras()

return


; ============================================================
; HOTKEYS
; ============================================================

; CAMERA 1 - TALKING HEAD

^#1::
    AdjustS3(1, 1)
return

^#q::
    AdjustS3(1, -1)
return


; CAMERA 2 - OVERHEAD

^#2::
    AdjustS3(2, 1)
return

^#w::
    AdjustS3(2, -1)
return


; CAMERA 3 - SIDE

^#3::
    AdjustS3(3, 1)
return

^#e::
    AdjustS3(3, -1)
return


; CAMERA 4 - YOLOLIV S7

^#4::
    AdjustS7(1)
return

^#d::
    AdjustS7(-1)
return


; ALL CAMERAS - ZOOM IN

^#=::
    AdjustS3(1, 1)
    AdjustS3(2, 1)
    AdjustS3(3, 1)
    AdjustS7(1)
return


; ALL CAMERAS - ZOOM OUT

^#-::
    AdjustS3(1, -1)
    AdjustS3(2, -1)
    AdjustS3(3, -1)
    AdjustS7(-1)
return


; RE-SYNC ALL

^#r::
    InitializeCameras()
return


; ============================================================
; S7 AUTOFOCUS HOTKEYS
; ============================================================

; FACE FOCUS
;
; Ctrl + Win + F

^#f::
    S7FaceFocus()
return


; AUTO-FOCUS CENTER
;
; Ctrl + Win + A

^#a::
    S7AutoFocusCenter()
return


; ============================================================
; INITIALIZE ALL CAMERAS
; ============================================================

InitializeCameras()
{
    global S3Zoom1
    global S3Zoom2
    global S3Zoom3
    global S7Zoom
    global S7Min
    global S7Max

    Log("----------------------------------------")
    Log("Starting camera synchronization")

    Sleep, 500

    Result1 := SyncS3(1)
    Result2 := SyncS3(2)
    Result3 := SyncS3(3)

    Result4 := InitializeS7()

    Message := ""

    if (Result1)
        Message .= "Talking Head: " . S3Zoom1 . "%`n"
    else
        Message .= "Talking Head: FAILED`n"

    if (Result2)
        Message .= "Overhead: " . S3Zoom2 . "%`n"
    else
        Message .= "Overhead: FAILED`n"

    if (Result3)
        Message .= "Side: " . S3Zoom3 . "%`n"
    else
        Message .= "Side: FAILED`n"

    if (Result4)
    {
        S7Pct := Round(((S7Zoom - S7Min) / (S7Max - S7Min)) * 100)
        Message .= "Yololiv S7: " . S7Pct . "%"
    }
    else
    {
        Message .= "Yololiv S7: FAILED"
    }

    Log("Synchronization complete")
    Log("----------------------------------------")

    ToolTip, %Message%
    SetTimer, RemoveToolTip, -2500
}


; ============================================================
; S3 - GET CURRENT ZOOM
; ============================================================

GetS3Zoom(IP)
{
    global S3Exe

    TempFile := A_Temp . "\yolocam_s3_" . A_TickCount . ".txt"

    ; Build a fully quoted CMD command.
    ;
    ; /S /C ""EXE" arguments > "file" 2>&1"
    ;
    ; RunWait with Hide prevents any terminal window from
    ; appearing.

    Command := ComSpec . " /S /C """"" . S3Exe . """ " . IP . " get > """ . TempFile . """ 2>&1"""

    Log("S3 GET command: " . Command)

    RunWait, %Command%, %A_ScriptDir%, Hide

    Sleep, 50

    if !FileExist(TempFile)
    {
        Log("S3 GET FAILED - output file missing: " . IP)
        return ""
    }

    FileRead, Output, %TempFile%

    FileDelete, %TempFile%

    Log("S3 GET output [" . IP . "]: [" . Output . "]")

    ; Expected output:
    ;
    ; 1.00 0.500 0.500
    ; 1.25 0.500 0.500

    if RegExMatch(Output, "^\s*(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)", Match)
    {
        ZoomFactor := Match1 + 0

        Log("S3 GET parsed [" . IP . "]: " . ZoomFactor)

        return ZoomFactor
    }

    Log("S3 GET PARSE FAILED [" . IP . "]")

    return ""
}


; ============================================================
; S3 - SET ZOOM
; ============================================================

SetS3Zoom(IP, Pct)
{
    global S3Exe

    ; Convert:
    ;
    ; 0%   = 1.00x
    ; 25%  = 1.75x
    ; 50%  = 2.50x
    ; 75%  = 3.25x
    ; 100% = 4.00x

    ZoomFactor := 1.0 + (Pct / 100.0 * 3.0)
    ZoomFactor := Round(ZoomFactor, 2)

    Command := """" . S3Exe . """ " . IP . " set " . ZoomFactor

    Log("S3 SET command: " . Command)

    ; Run directly and hidden.
    RunWait, %Command%, %A_ScriptDir%, Hide

    return true
}


; ============================================================
; S3 - SYNC CAMERA
; ============================================================

SyncS3(CameraNum)
{
    global S3IP1
    global S3IP2
    global S3IP3

    global S3Zoom1
    global S3Zoom2
    global S3Zoom3

    IP := ""

    if (CameraNum = 1)
        IP := S3IP1
    else if (CameraNum = 2)
        IP := S3IP2
    else if (CameraNum = 3)
        IP := S3IP3
    else
        return false

    Log("Syncing S3 Camera " . CameraNum . " at " . IP)

    ZoomFactor := GetS3Zoom(IP)

    if (ZoomFactor = "")
    {
        Log("SYNC FAILED - Camera " . CameraNum . " - " . IP)
        return false
    }

    ; Convert S3 zoom factor to percentage.
    ;
    ; 1.00 = 0%
    ; 4.00 = 100%

    Pct := Round(((ZoomFactor - 1.0) / 3.0) * 100)

    if (Pct < 0)
        Pct := 0

    if (Pct > 100)
        Pct := 100

    if (CameraNum = 1)
        S3Zoom1 := Pct
    else if (CameraNum = 2)
        S3Zoom2 := Pct
    else if (CameraNum = 3)
        S3Zoom3 := Pct

    Log("SYNC OK - Camera " . CameraNum . " - " . ZoomFactor . "x = " . Pct . "%")

    return true
}


; ============================================================
; S3 - ADJUST ZOOM
; ============================================================

AdjustS3(CameraNum, Direction)
{
    global ZoomStepPct

    global S3Zoom1
    global S3Zoom2
    global S3Zoom3

    global S3IP1
    global S3IP2
    global S3IP3

    if (CameraNum = 1)
    {
        Pct := S3Zoom1
        IP := S3IP1
    }
    else if (CameraNum = 2)
    {
        Pct := S3Zoom2
        IP := S3IP2
    }
    else if (CameraNum = 3)
    {
        Pct := S3Zoom3
        IP := S3IP3
    }
    else
    {
        return
    }

    NewPct := Pct + (Direction * ZoomStepPct)

    if (NewPct < 0)
        NewPct := 0

    if (NewPct > 100)
        NewPct := 100

    if (NewPct = Pct)
    {
        ShowZoom(CameraNum, NewPct)
        return
    }

    if SetS3Zoom(IP, NewPct)
    {
        if (CameraNum = 1)
            S3Zoom1 := NewPct
        else if (CameraNum = 2)
            S3Zoom2 := NewPct
        else if (CameraNum = 3)
            S3Zoom3 := NewPct

        Log("Camera " . CameraNum . " zoom: " . Pct . "% -> " . NewPct . "%")

        ShowZoom(CameraNum, NewPct)
    }
}


; ============================================================
; S7 - INITIALIZE
; ============================================================

InitializeS7()
{
    global CamParamExe
    global S7Serial
    global S7ID

    Log("Initializing Yololiv S7")

    if !FileExist(CamParamExe)
    {
        Log("S7 ERROR: CamParam.exe not found")
        return false
    }

    TempFile := A_Temp . "\camparam_scan_" . A_TickCount . ".txt"

    ; Hidden command:
    ;
    ; CamParam.exe > temporary-file

    Command := ComSpec . " /S /C """"" . CamParamExe . """ > """ . TempFile . """ 2>&1"""

    Log("S7 scan command: " . Command)

    RunWait, %Command%, %A_ScriptDir%, Hide

    Sleep, 50

    if !FileExist(TempFile)
    {
        Log("S7 ERROR: Scan output missing")
        return false
    }

    FileRead, ScanOutput, %TempFile%

    FileDelete, %TempFile%

    Log("S7 scan output: " . ScanOutput)

    FoundID := -1

    Loop, Parse, ScanOutput, `n, `r
    {
        Line := A_LoopField

        if InStr(Line, S7Serial)
        {
            if RegExMatch(Line, "\d+", Match)
            {
                FoundID := Match
                break
            }
        }
    }

    if (FoundID = -1)
    {
        Log("S7 ERROR: Serial not found: " . S7Serial)
        return false
    }

    S7ID := FoundID

    Log("S7 found. Device ID = " . S7ID)

    return SyncS7()
}


; ============================================================
; S7 - SYNC
; ============================================================

SyncS7()
{
    global CamParamExe
    global S7ID
    global S7Min
    global S7Max
    global S7Zoom

    if (S7ID = -1)
    {
        Log("S7 SYNC FAILED: Device ID unknown")
        return false
    }

    TempFile := A_Temp . "\camparam_zoom_" . A_TickCount . ".txt"

    Command := ComSpec . " /S /C """"" . CamParamExe . """ device " . S7ID . " zoom > """ . TempFile . """ 2>&1"""

    Log("S7 zoom GET command: " . Command)

    RunWait, %Command%, %A_ScriptDir%, Hide

    Sleep, 50

    if !FileExist(TempFile)
    {
        Log("S7 ERROR: Zoom output missing")
        return false
    }

    FileRead, Output, %TempFile%

    FileDelete, %TempFile%

    Log("S7 zoom output: " . Output)

    if RegExMatch(Output, "(\d+)", Match)
    {
        Value := Match1 + 0

        if (Value >= S7Min && Value <= S7Max)
        {
            S7Zoom := Value

            Log("S7 SYNC OK: " . S7Zoom)

            return true
        }
    }

    Log("S7 SYNC PARSE FAILED")

    return false
}


; ============================================================
; S7 - SET ZOOM
; ============================================================

SetS7Zoom(Value)
{
    global CamParamExe
    global S7ID

    if (S7ID = -1)
    {
        Log("S7 SET FAILED: Device ID unknown")
        return false
    }

    Command := """" . CamParamExe . """ device " . S7ID . " zoom " . Value

    Log("S7 SET command: " . Command)

    RunWait, %Command%, %A_ScriptDir%, Hide

    return true
}


; ============================================================
; S7 - ADJUST ZOOM
; ============================================================

AdjustS7(Direction)
{
    global ZoomStepPct
    global S7Zoom
    global S7Min
    global S7Max

    if (S7Zoom < S7Min)
        S7Zoom := S7Min

    Range := S7Max - S7Min

    Step := Round(Range * ZoomStepPct / 100)

    if (Step < 1)
        Step := 1

    NewZoom := S7Zoom + (Direction * Step)

    if (NewZoom < S7Min)
        NewZoom := S7Min

    if (NewZoom > S7Max)
        NewZoom := S7Max

    if (NewZoom = S7Zoom)
    {
        Pct := Round(((NewZoom - S7Min) / (S7Max - S7Min)) * 100)
        ShowZoom(4, Pct)
        return
    }

    if SetS7Zoom(NewZoom)
    {
        S7Zoom := NewZoom

        Pct := Round(((NewZoom - S7Min) / (S7Max - S7Min)) * 100)

        Log("S7 zoom: " . S7Zoom . " (" . Pct . "%)")

        ShowZoom(4, Pct)
    }
}


; ============================================================
; S7 - FACE FOCUS
; ============================================================

S7FaceFocus()
{
    global S7FocusIP
    global S7FocusPort

    ; Captured Face Focus payload:
    ;
    ; 08 01 00 00 12 00 00 00 a5 00 00 00
    ; 0a af 08 02 10 31 28 17 32 02 08 04
    ; 28 5a

    Data := Chr(0x08) . Chr(0x01) . Chr(0x00) . Chr(0x00) . Chr(0x12) . Chr(0x00) . Chr(0x00) . Chr(0x00) . Chr(0xA5) . Chr(0x00) . Chr(0x00) . Chr(0x00) . Chr(0x0A) . Chr(0xAF) . Chr(0x08) . Chr(0x02) . Chr(0x10) . Chr(0x31) . Chr(0x28) . Chr(0x17) . Chr(0x32) . Chr(0x02) . Chr(0x08) . Chr(0x04) . Chr(0x28) . Chr(0x5A)

    Log("S7 Face Focus command")

    if SendS7FocusPacket(S7FocusIP, S7FocusPort, Data)
    {
        Log("S7 Face Focus: SUCCESS")

        ToolTip, S7 Face Focus
        SetTimer, RemoveToolTip, -1000
    }
    else
    {
        Log("S7 Face Focus: FAILED")

        ToolTip, S7 Face Focus FAILED
        SetTimer, RemoveToolTip, -1500
    }
}


; ============================================================
; S7 - AUTOFOCUS CENTER
; ============================================================

S7AutoFocusCenter()
{
    global S7FocusIP
    global S7FocusPort

    ; Captured Auto-Focus Center payload:
    ;
    ; 08 01 00 00 12 00 00 00 a5 00 00 00
    ; 0a af 08 02 10 33 28 17 32 02 08 03
    ; 2d 5a

    Data := Chr(0x08) . Chr(0x01) . Chr(0x00) . Chr(0x00) . Chr(0x12) . Chr(0x00) . Chr(0x00) . Chr(0x00) . Chr(0xA5) . Chr(0x00) . Chr(0x00) . Chr(0x00) . Chr(0x0A) . Chr(0xAF) . Chr(0x08) . Chr(0x02) . Chr(0x10) . Chr(0x33) . Chr(0x28) . Chr(0x17) . Chr(0x32) . Chr(0x02) . Chr(0x08) . Chr(0x03) . Chr(0x2D) . Chr(0x5A)

    Log("S7 Auto-Focus Center command")

    if SendS7FocusPacket(S7FocusIP, S7FocusPort, Data)
    {
        Log("S7 Auto-Focus Center: SUCCESS")

        ToolTip, S7 Auto-Focus Center
        SetTimer, RemoveToolTip, -1000
    }
    else
    {
        Log("S7 Auto-Focus Center: FAILED")

        ToolTip, S7 Auto-Focus Center FAILED
        SetTimer, RemoveToolTip, -1500
    }
}


; ============================================================
; S7 - SEND TCP FOCUS PACKET
; ============================================================

SendS7FocusPacket(IP, Port, Data)
{
    ; --------------------------------------------------------
    ; Initialize Winsock
    ; --------------------------------------------------------

    VarSetCapacity(WSAData, 394, 0)

    Result := DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", &WSAData)

    if (Result != 0)
    {
        Log("Winsock WSAStartup failed: " . Result)
        return false
    }


    ; --------------------------------------------------------
    ; Create TCP socket
    ; --------------------------------------------------------

    Socket := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")

    if (Socket = -1)
    {
        ErrorCode := DllCall("Ws2_32\WSAGetLastError")

        Log("S7 socket creation failed: " . ErrorCode)

        DllCall("Ws2_32\WSACleanup")

        return false
    }


    ; --------------------------------------------------------
    ; Build sockaddr_in
    ; --------------------------------------------------------

    VarSetCapacity(SockAddr, 16, 0)

    ; AF_INET
    NumPut(2, SockAddr, 0, "UShort")

    ; Port
    NetworkPort := DllCall("Ws2_32\htons", "UShort", Port, "UShort")

    NumPut(NetworkPort, SockAddr, 2, "UShort")

    ; IP address
    IPAddress := DllCall("Ws2_32\inet_addr", "AStr", IP, "UInt")

    if (IPAddress = 0xFFFFFFFF)
    {
        Log("S7 invalid IP address: " . IP)

        DllCall("Ws2_32\closesocket", "Ptr", Socket)
        DllCall("Ws2_32\WSACleanup")

        return false
    }

    NumPut(IPAddress, SockAddr, 4, "UInt")


    ; --------------------------------------------------------
    ; Connect
    ; --------------------------------------------------------

    Result := DllCall("Ws2_32\connect", "Ptr", Socket, "Ptr", &SockAddr, "Int", 16)

    if (Result != 0)
    {
        ErrorCode := DllCall("Ws2_32\WSAGetLastError")

        Log("S7 TCP connect failed: " . IP . ":" . Port . " error=" . ErrorCode)

        DllCall("Ws2_32\closesocket", "Ptr", Socket)
        DllCall("Ws2_32\WSACleanup")

        return false
    }


    ; --------------------------------------------------------
    ; Send payload
    ; --------------------------------------------------------

    DataLength := StrLen(Data)

    Sent := DllCall("Ws2_32\send", "Ptr", Socket, "Ptr", &Data, "Int", DataLength, "Int", 0, "Int")

    if (Sent != DataLength)
    {
        ErrorCode := DllCall("Ws2_32\WSAGetLastError")

        Log("S7 TCP send failed: sent=" . Sent . " expected=" . DataLength . " error=" . ErrorCode)

        DllCall("Ws2_32\closesocket", "Ptr", Socket)
        DllCall("Ws2_32\WSACleanup")

        return false
    }


    ; Give the camera a moment to process the command.

    Sleep, 50


    ; --------------------------------------------------------
    ; Close connection
    ; --------------------------------------------------------

    DllCall("Ws2_32\closesocket", "Ptr", Socket)

    DllCall("Ws2_32\WSACleanup")

    Log("S7 TCP packet sent successfully: " . DataLength . " bytes")

    return true
}


; ============================================================
; TOOLTIP
; ============================================================

ShowZoom(CameraNum, Pct)
{
    if (CameraNum = 1)
        Name := "Talking Head"
    else if (CameraNum = 2)
        Name := "Overhead"
    else if (CameraNum = 3)
        Name := "Side"
    else if (CameraNum = 4)
        Name := "Yololiv S7"
    else
        Name := "Camera"

    ToolTip, %Name% Zoom: %Pct%`%
    SetTimer, RemoveToolTip, -800
}


RemoveToolTip:
    ToolTip
return


; ============================================================
; LOGGING
; ============================================================

Log(Message)
{
    global LogFolder
    global LogFileName

    FormatTime, TimeStamp,, yyyy-MM-dd HH:mm:ss

    FileAppend, %TimeStamp% - %Message%`r`n, %LogFolder%\%LogFileName%
}