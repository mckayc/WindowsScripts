#Requires AutoHotkey v1.1.36+
#NoEnv
#SingleInstance Force
#UseHook On
SendMode Input
SetWorkingDir %A_ScriptDir%

; ============================================================
; Webcam Zoom + Focus Controller
;
; Camera 1 - Talking Head : Yololiv S7 (zoom over USB with
;                           CamParam.exe, focus over TCP)
; Camera 2 - Top Down     : YoloCam S3 (zoom with S3 tool)
; Camera 3 - Side         : YoloCam S3 (zoom with S3 tool)
;
; AutoHotkey v1.1.36.02 Unicode 64-bit
; ============================================================

global ZoomStepPct := 5

global CameraNames := {1: "Talking Head", 2: "Top Down", 3: "Side"}


; ============================================================
; S3 SETTINGS
; ============================================================

global S3Exe := A_ScriptDir . "\yolocam-s3-zoom\yolocam-s3-zoom-multi-win64.exe"

; Keyed by camera number.
global S3IP := {2: "192.168.124.10", 3: "192.168.123.10"}

; Current zoom per camera, 0-100%.
global S3Zoom := {2: 0, 3: 0}


; ============================================================
; S7 SETTINGS
; ============================================================

global S7Serial := "Y-CAM-26020026"

global S7Min := 50
global S7Max := 98
global S7ID := -1
global S7Zoom := 50

global CamParamExe := A_ScriptDir . "\CamParam.exe"


; ============================================================
; S7 FOCUS NETWORK SETTINGS
; ============================================================

global S7FocusIP := "192.168.127.10"
global S7FocusPort := 12345

; Captured application protocol uses an incrementing
; transaction counter. Kept in the range 1-127 so it
; always encodes as a single protobuf varint byte.
global S7FocusCounter := 0x31

; TCP socket. Opened per focus command and closed after
; the reply, the same way Compose does it.
global S7FocusSocket := -1

; Winsock initialization state.
global S7WinsockStarted := false

; Prevent overlapping focus commands.
global S7FocusBusy := false

; Focus networking timeouts.
global S7ConnectTimeoutMs := 1000
global S7SendTimeoutMs := 500

; How long to wait for the camera's reply to a request.
; Face-tracking events arriving meanwhile are skipped.
global S7ReplyTimeoutMs := 1500

; How long to wait for the camera to close its side of the
; connection after we finish.
global S7CloseTimeoutMs := 1000


; ============================================================
; LOGGING
; ============================================================

global LogFolder := A_ScriptDir . "\logs"
global LogFileName := "webcamzoom.log"

; When the log passes this size it is renamed to
; LogOldFileName (replacing any previous one) and a new
; log is started.
global LogMaxBytes := 1024 * 1024
global LogOldFileName := "webcamzoom.old.log"


; ============================================================
; STARTUP
; ============================================================

if !FileExist(LogFolder)
    FileCreateDir, %LogFolder%

OnExit("WebcamZoomExit")

Log("========================================")
Log("Webcam Zoom Controller starting")
Log("S3 EXE: " . S3Exe)
Log("S3 Top Down IP: " . S3IP[2])
Log("S3 Side IP: " . S3IP[3])
Log("S7 Serial: " . S7Serial)
Log("S7 Focus IP: " . S7FocusIP)
Log("S7 Focus Port: " . S7FocusPort)
Log("S7 Focus Counter: " . Format("{:02X}", S7FocusCounter))
Log("========================================")

InitializeCameras()

return


; ============================================================
; HOTKEYS
; ============================================================


; ============================================================
; CAMERA 1 - TALKING HEAD (S7)
; ============================================================

^#1::
    Log("HOTKEY: Ctrl+Win+1")
    AdjustS7(1)
return

^#q::
    Log("HOTKEY: Ctrl+Win+Q")
    AdjustS7(-1)
return


; ============================================================
; CAMERA 2 - TOP DOWN (S3)
; ============================================================

^#2::
    Log("HOTKEY: Ctrl+Win+2")
    AdjustS3(2, 1)
return

^#w::
    Log("HOTKEY: Ctrl+Win+W")
    AdjustS3(2, -1)
return


; ============================================================
; CAMERA 3 - SIDE (S3)
; ============================================================

^#3::
    Log("HOTKEY: Ctrl+Win+3")
    AdjustS3(3, 1)
return

^#e::
    Log("HOTKEY: Ctrl+Win+E")
    AdjustS3(3, -1)
return


; ============================================================
; TALKING HEAD (S7) FOCUS
; ============================================================

^#f::
    Log("HOTKEY: Ctrl+Win+F")
    S7FaceFocus()
return

^#a::
    Log("HOTKEY: Ctrl+Win+A")
    S7AFCFocus()
return


; ============================================================
; ALL CAMERAS - ZOOM IN
; ============================================================

^#=::
    Log("HOTKEY: Ctrl+Win+=")
    AdjustS7(1)
    AdjustS3(2, 1)
    AdjustS3(3, 1)
return


; ============================================================
; ALL CAMERAS - ZOOM OUT
; ============================================================

^#-::
    Log("HOTKEY: Ctrl+Win+-")
    AdjustS7(-1)
    AdjustS3(2, -1)
    AdjustS3(3, -1)
return


; ============================================================
; RE-SYNC ALL
; ============================================================

^#r::
    Log("HOTKEY: Ctrl+Win+R")
    InitializeCameras()
return


; ============================================================
; INITIALIZE ALL CAMERAS
; ============================================================

InitializeCameras()
{
    global S3IP
    global S3Zoom
    global CameraNames

    Log("----------------------------------------")
    Log("Starting camera synchronization")

    Sleep, 500

    Message := ""

    if InitializeS7()
        Message .= CameraNames[1] . ": " . S7ZoomPct() . "%`n"
    else
        Message .= CameraNames[1] . ": FAILED`n"

    for CameraNum in S3IP
    {
        if SyncS3(CameraNum)
            Message .= CameraNames[CameraNum] . ": " . S3Zoom[CameraNum] . "%`n"
        else
            Message .= CameraNames[CameraNum] . ": FAILED`n"
    }

    Message := RTrim(Message, "`n")

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

    ; 0%   = 1.00x
    ; 25%  = 1.75x
    ; 50%  = 2.50x
    ; 75%  = 3.25x
    ; 100% = 4.00x

    ZoomFactor := 1.0 + (Pct / 100.0 * 3.0)
    ZoomFactor := Round(ZoomFactor, 2)

    Command := """" . S3Exe . """ " . IP . " set " . ZoomFactor

    Log("S3 SET command: " . Command)

    RunWait, %Command%, %A_ScriptDir%, Hide

    return true
}


; ============================================================
; S3 - SYNC CAMERA
; ============================================================

SyncS3(CameraNum)
{
    global S3IP
    global S3Zoom
    global CameraNames

    if !S3IP.HasKey(CameraNum)
        return false

    IP := S3IP[CameraNum]

    Log("Syncing S3 " . CameraNames[CameraNum] . " at " . IP)

    ZoomFactor := GetS3Zoom(IP)

    if (ZoomFactor = "")
    {
        Log("SYNC FAILED - " . CameraNames[CameraNum] . " - " . IP)
        return false
    }

    Pct := Round(((ZoomFactor - 1.0) / 3.0) * 100)

    if (Pct < 0)
        Pct := 0

    if (Pct > 100)
        Pct := 100

    S3Zoom[CameraNum] := Pct

    Log("SYNC OK - " . CameraNames[CameraNum] . " - " . ZoomFactor . "x = " . Pct . "%")

    return true
}


; ============================================================
; S3 - ADJUST ZOOM
; ============================================================

AdjustS3(CameraNum, Direction)
{
    global ZoomStepPct
    global S3IP
    global S3Zoom
    global CameraNames

    if !S3IP.HasKey(CameraNum)
        return

    IP := S3IP[CameraNum]
    Pct := S3Zoom[CameraNum]

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
        S3Zoom[CameraNum] := NewPct

        Log(CameraNames[CameraNum] . " zoom: " . Pct . "% -> " . NewPct . "%")

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
; S7 - SYNC ZOOM
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
; S7 - ZOOM AS A PERCENTAGE OF ITS RANGE
; ============================================================

S7ZoomPct()
{
    global S7Zoom
    global S7Min
    global S7Max

    return Round(((S7Zoom - S7Min) / (S7Max - S7Min)) * 100)
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
        ShowZoom(1, S7ZoomPct())
        return
    }

    if SetS7Zoom(NewZoom)
    {
        S7Zoom := NewZoom

        Log("S7 zoom: " . S7Zoom . " (" . S7ZoomPct() . "%)")

        ShowZoom(1, S7ZoomPct())
    }
}


; ============================================================
; S7 - FACE FOCUS
; ============================================================

S7FaceFocus()
{
    ; Mode 4 = Face Focus (derived from Wireshark capture)
    SendS7FocusCommand(4, "Face Focus")
}


; ============================================================
; S7 - AF-C FOCUS
; ============================================================

S7AFCFocus()
{
    ; Mode 3 = AF-C (derived from Wireshark capture)
    SendS7FocusCommand(3, "AF-C")
}


; ============================================================
; S7 - SEND FOCUS COMMAND
;
; Same sequence Compose uses:
;   1. Refuse if another program is connected to the camera.
;      Two simultaneous connections can wedge the camera
;      until it is power cycled.
;   2. Connect.
;   3. Set the focus mode and wait for the matching reply.
;   4. Read the focus mode back to confirm it changed.
;   5. Close.
; ============================================================

SendS7FocusCommand(Mode, Description)
{
    global S7FocusBusy

    ; Prevent multiple focus commands from overlapping.
    if (S7FocusBusy)
    {
        Log("S7 FOCUS: Command ignored because another focus command is active")
        return false
    }

    S7FocusBusy := true

    Log("----------------------------------------")
    Log("S7 FOCUS: " . Description . " (mode " . Mode . ")")

    OtherClient := GetS7OtherClient()

    if (OtherClient != "")
    {
        Log("S7 FOCUS ABORTED: camera already connected to " . OtherClient)
        ShowFocusStatus("S7 Focus: " . OtherClient . " is connected to the camera.`nClose it first.", 3000)
        S7FocusBusy := false
        return false
    }

    if !EnsureS7FocusConnection()
    {
        Log("S7 FOCUS FAILED: Could not establish TCP connection")
        ShowFocusStatus("S7 Focus: CONNECTION FAILED")
        S7FocusBusy := false
        return false
    }

    ; Set: type 2, counter, command 23 (focus mode), params {1: Mode}
    SetCounter := NextS7FocusCounter()
    Reply := SendS7FocusRequest([0x08, 0x02, 0x10, SetCounter, 0x28, 0x17, 0x32, 0x02, 0x08, Mode], SetCounter)

    if (!IsObject(Reply) || Reply.Status != 200)
    {
        Status := IsObject(Reply) ? "status " . Reply.Status : "no reply"

        Log("S7 FOCUS SET FAILED: " . Status)

        CloseS7FocusConnection()

        ShowFocusStatus("S7 Focus: " . Description . " FAILED (" . Status . ")", 3000)

        S7FocusBusy := false

        return false
    }

    ; Get: type 1, counter, command 23 (focus mode)
    GetCounter := NextS7FocusCounter()
    Reply := SendS7FocusRequest([0x08, 0x01, 0x10, GetCounter, 0x28, 0x17], GetCounter)

    CloseS7FocusConnection()

    ActualMode := IsObject(Reply) ? GetS7ProtoField(Reply.Params, 1) : ""

    Log("S7 FOCUS read-back mode: " . (ActualMode = "" ? "unknown" : ActualMode))
    Log("----------------------------------------")

    if (ActualMode = Mode)
        ShowFocusStatus("S7 Focus: " . Description)
    else if (ActualMode = "")
        ShowFocusStatus("S7 Focus: " . Description . " sent (not confirmed)", 3000)
    else
        ShowFocusStatus("S7 Focus: asked for " . Description . ", camera reports " . S7FocusModeName(ActualMode), 3000)

    S7FocusBusy := false

    return true
}


; ============================================================
; S7 - FOCUS MODE NAME
; ============================================================

S7FocusModeName(Mode)
{
    if (Mode = 3)
        return "AF-C"

    if (Mode = 4)
        return "Face Focus"

    return "mode " . Mode
}


; ============================================================
; S7 - NEXT TRANSACTION COUNTER
;
; Returns the counter to use and advances it, staying in
; 1-127 so it always encodes as one protobuf varint byte.
; ============================================================

NextS7FocusCounter()
{
    global S7FocusCounter

    Counter := S7FocusCounter

    if (Counter < 1 || Counter > 127)
        Counter := 1

    S7FocusCounter := Mod(Counter, 127) + 1

    return Counter
}


; ============================================================
; S7 - FIND ANOTHER PROGRAM CONNECTED TO THE CAMERA
;
; Returns the process name (or PID) holding an established
; connection to the camera's control port, or "" if none.
; ============================================================

GetS7OtherClient()
{
    global S7FocusIP
    global S7FocusPort

    TempFile := A_Temp . "\s7_netstat_" . A_TickCount . ".txt"

    Command := ComSpec . " /C netstat -ano -p TCP > """ . TempFile . """"

    RunWait, %Command%, %A_ScriptDir%, Hide

    FileRead, Output, %TempFile%

    FileDelete, %TempFile%

    Remote := S7FocusIP . ":" . S7FocusPort

    Loop, Parse, Output, `n, `r
    {
        ; Columns: Proto, Local Address, Foreign Address, State, PID
        Columns := StrSplit(RegExReplace(Trim(A_LoopField), "\s+", " "), " ")

        if (Columns.Length() >= 5 && Columns[3] = Remote && Columns[4] = "ESTABLISHED")
        {
            Pid := Columns[5]
            Name := GetProcessNameFromPid(Pid)

            return (Name != "") ? Name : "PID " . Pid
        }
    }

    return ""
}


GetProcessNameFromPid(Pid)
{
    try
    {
        for Process in ComObjGet("winmgmts:").ExecQuery("SELECT Name FROM Win32_Process WHERE ProcessId=" . Pid)
            return Process.Name
    }

    return ""
}


; ============================================================
; S7 - SEND REQUEST AND WAIT FOR ITS REPLY
;
; Body is the protobuf body as an array of bytes. Returns
; the parsed reply message, or "" on failure.
; ============================================================

SendS7FocusRequest(Body, Counter)
{
    global S7ReplyTimeoutMs

    Length := BuildS7Packet(Body, Packet)

    Log("S7 FOCUS TX: " . S7BufferToHex(Packet, Length))

    Sent := SendS7FocusData(Packet, Length)

    if (Sent != Length)
    {
        ErrorCode := DllCall("Ws2_32\WSAGetLastError")

        Log("S7 FOCUS SEND FAILED. Sent=" . Sent . " Error=" . ErrorCode)

        return ""
    }

    return WaitForS7Reply(Counter, S7ReplyTimeoutMs)
}


; ============================================================
; S7 - BUILD PACKET
;
; Captured format:
;
; 08 01 00 00               header (01 = PC->camera)
; LEN LEN LEN LEN           length of everything after this field
; A5 00 00 00               marker
; BODYLEN (A5^BODYLEN)      body length and its check byte
; BODY...                   protobuf body
; CHECKSUM                  XOR of all body bytes
; 5A                        end marker
;
; Returns the packet length.
; ============================================================

BuildS7Packet(Body, ByRef Packet)
{
    BodyLength := Body.Length()
    Length := 16 + BodyLength

    VarSetCapacity(Packet, Length, 0)

    NumPut(0x08, Packet, 0, "UChar")
    NumPut(0x01, Packet, 1, "UChar")

    NumPut(Length - 8, Packet, 4, "UInt")

    NumPut(0xA5, Packet, 8, "UChar")

    NumPut(BodyLength, Packet, 12, "UChar")
    NumPut(0xA5 ^ BodyLength, Packet, 13, "UChar")

    Checksum := 0

    for Index, Value in Body
    {
        NumPut(Value, Packet, 13 + Index, "UChar")
        Checksum ^= Value
    }

    NumPut(Checksum, Packet, 14 + BodyLength, "UChar")
    NumPut(0x5A, Packet, 15 + BodyLength, "UChar")

    return Length
}


; ============================================================
; S7 - ENSURE FOCUS TCP CONNECTION
; ============================================================

EnsureS7FocusConnection()
{
    global S7FocusIP
    global S7FocusPort
    global S7FocusSocket
    global S7WinsockStarted
    global S7ConnectTimeoutMs

    if (S7FocusSocket != -1)
        return true

    Log("S7 FOCUS: Opening TCP connection")

    ; --------------------------------------------------------
    ; Start Winsock
    ; --------------------------------------------------------

    if !S7WinsockStarted
    {
        VarSetCapacity(WSAData, 400, 0)

        Result := DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", &WSAData, "Int")

        if (Result != 0)
        {
            Log("S7 FOCUS: WSAStartup failed: " . Result)
            return false
        }

        S7WinsockStarted := true

        Log("S7 FOCUS: Winsock initialized")
    }

    ; --------------------------------------------------------
    ; Create TCP socket
    ; --------------------------------------------------------

    Socket := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")

    if (Socket = -1)
    {
        ErrorCode := DllCall("Ws2_32\WSAGetLastError")

        Log("S7 FOCUS: socket() failed: " . ErrorCode)

        return false
    }

    ; --------------------------------------------------------
    ; Make socket non-blocking.
    ; FIONBIO = 0x8004667E
    ; --------------------------------------------------------

    NonBlocking := 1

    Result := DllCall("Ws2_32\ioctlsocket"
        , "Ptr", Socket
        , "UInt", 0x8004667E
        , "UInt*", NonBlocking
        , "Int")

    if (Result != 0)
    {
        ErrorCode := DllCall("Ws2_32\WSAGetLastError")

        Log("S7 FOCUS: ioctlsocket() failed: " . ErrorCode)

        DllCall("Ws2_32\closesocket", "Ptr", Socket)

        return false
    }

    Log("S7 FOCUS: Socket set to non-blocking")

    ; --------------------------------------------------------
    ; Build sockaddr_in
    ; --------------------------------------------------------

    VarSetCapacity(SocketAddress, 16, 0)

    NumPut(2, SocketAddress, 0, "UShort")

    PortNetwork := DllCall("Ws2_32\htons", "UShort", S7FocusPort, "UShort")

    NumPut(PortNetwork, SocketAddress, 2, "UShort")

    IPAddress := DllCall("Ws2_32\inet_addr", "AStr", S7FocusIP, "UInt")

    NumPut(IPAddress, SocketAddress, 4, "UInt")

    ; --------------------------------------------------------
    ; Start non-blocking connect
    ; --------------------------------------------------------

    Result := DllCall("Ws2_32\connect"
        , "Ptr", Socket
        , "Ptr", &SocketAddress
        , "Int", 16
        , "Int")

    if (Result = 0)
    {
        S7FocusSocket := Socket

        Log("S7 FOCUS: TCP connection established immediately")

        return true
    }

    ErrorCode := DllCall("Ws2_32\WSAGetLastError")

    if (ErrorCode != 10035 && ErrorCode != 10036 && ErrorCode != 10037)
    {
        Log("S7 FOCUS: connect() failed: " . ErrorCode)

        DllCall("Ws2_32\closesocket", "Ptr", Socket)

        return false
    }

    Log("S7 FOCUS: Connect in progress")

    if !WaitForS7Socket(Socket, 2, S7ConnectTimeoutMs)
    {
        Log("S7 FOCUS: TCP connection timed out")

        DllCall("Ws2_32\closesocket", "Ptr", Socket)

        return false
    }

    ; --------------------------------------------------------
    ; Check SO_ERROR.
    ; --------------------------------------------------------

    SOError := 0
    OptLen := 4

    GetsockResult := DllCall("Ws2_32\getsockopt"
        , "Ptr", Socket
        , "Int", 0xFFFF
        , "Int", 0x1007
        , "Int*", SOError
        , "Int*", OptLen
        , "Int")

    if (GetsockResult != 0)
    {
        ErrorCode := DllCall("Ws2_32\WSAGetLastError")

        Log("S7 FOCUS: getsockopt() failed: " . ErrorCode)

        DllCall("Ws2_32\closesocket", "Ptr", Socket)

        return false
    }

    if (SOError != 0)
    {
        Log("S7 FOCUS: TCP connection failed. SO_ERROR=" . SOError)

        DllCall("Ws2_32\closesocket", "Ptr", Socket)

        return false
    }

    S7FocusSocket := Socket

    Log("S7 FOCUS: TCP connection established")

    return true
}


; ============================================================
; S7 - SEND DATA WITH TIMEOUT
; ============================================================

SendS7FocusData(ByRef Buffer, Length)
{
    global S7FocusSocket
    global S7SendTimeoutMs

    TotalSent := 0

    while (TotalSent < Length)
    {
        if !WaitForS7Socket(S7FocusSocket, 2, S7SendTimeoutMs)
        {
            Log("S7 FOCUS SEND: Send timeout")

            return TotalSent
        }

        Remaining := Length - TotalSent

        Sent := DllCall("Ws2_32\send"
            , "Ptr", S7FocusSocket
            , "Ptr", (&Buffer + TotalSent)
            , "Int", Remaining
            , "Int", 0
            , "Int")

        if (Sent <= 0)
        {
            ErrorCode := DllCall("Ws2_32\WSAGetLastError")

            Log("S7 FOCUS SEND: send() failed. Error=" . ErrorCode)

            return TotalSent
        }

        TotalSent += Sent
    }

    return TotalSent
}


; ============================================================
; S7 - WAIT FOR REPLY
;
; Reads until a reply (type 4) with the given counter
; arrives. Face-tracking events (type 5) that arrive in the
; meantime are counted and skipped. TCP may split or join
; messages, so bytes are buffered and split by the length
; field. Returns the parsed reply, or "" on timeout.
; ============================================================

WaitForS7Reply(Counter, TimeoutMs)
{
    global S7FocusSocket

    Pending := []
    EventCount := 0
    Deadline := A_TickCount + TimeoutMs

    VarSetCapacity(Chunk, 2048, 0)

    Loop
    {
        Remaining := Deadline - A_TickCount

        if (Remaining <= 0)
            break

        if !WaitForS7Socket(S7FocusSocket, 1, Remaining)
            break

        Received := DllCall("Ws2_32\recv"
            , "Ptr", S7FocusSocket
            , "Ptr", &Chunk
            , "Int", 2048
            , "Int", 0
            , "Int")

        if (Received = 0)
        {
            Log("S7 FOCUS RX: Camera closed TCP connection")
            break
        }

        if (Received < 0)
        {
            ErrorCode := DllCall("Ws2_32\WSAGetLastError")
            Log("S7 FOCUS RX: recv() error " . ErrorCode)
            break
        }

        Loop, %Received%
            Pending.Push(NumGet(Chunk, A_Index - 1, "UChar"))

        while IsObject(Message := TakeS7Message(Pending))
        {
            if (Message.Type = 5)
            {
                EventCount++
                continue
            }

            Log("S7 FOCUS RX: type=" . Message.Type
                . " counter=" . Message.Counter
                . " status=" . Message.Status
                . " command=" . Message.Command
                . " : " . Message.Hex)

            if (Message.Type = 4 && Message.Counter = Counter)
            {
                if (EventCount > 0)
                    Log("S7 FOCUS RX: skipped " . EventCount . " face-tracking event(s)")

                return Message
            }
        }
    }

    Log("S7 FOCUS RX: no reply for counter " . Counter . " (skipped " . EventCount . " event(s))")

    return ""
}


; ============================================================
; S7 - TAKE ONE COMPLETE MESSAGE FROM THE RECEIVE BUFFER
;
; Removes and parses the first complete message in Pending
; (an array of bytes). Returns "" if none is complete yet.
; ============================================================

TakeS7Message(Pending)
{
    if (Pending.Length() < 8)
        return ""

    PayloadLength := Pending[5] | (Pending[6] << 8) | (Pending[7] << 16) | (Pending[8] << 24)

    ; Out of sync or garbage: drop everything buffered.
    if (PayloadLength < 8 || PayloadLength > 65536)
    {
        Log("S7 FOCUS RX: bad message length " . PayloadLength . ", discarding buffer")
        Pending.RemoveAt(1, Pending.Length())
        return ""
    }

    MessageLength := 8 + PayloadLength

    if (Pending.Length() < MessageLength)
        return ""

    Bytes := []

    Loop, %MessageLength%
        Bytes.Push(Pending[A_Index])

    Pending.RemoveAt(1, MessageLength)

    ; Body length at offset 12, body starts at offset 14.
    BodyLength := Bytes[13]
    Body := []

    Loop, %BodyLength%
        Body.Push(Bytes[14 + A_Index])

    Fields := ParseS7Proto(Body)

    return { Type: Fields[1]
        , Counter: Fields[2]
        , Status: Fields[4]
        , Command: Fields[5]
        , Params: Fields[6]
        , Hex: S7BytesToHex(Bytes) }
}


; ============================================================
; S7 - MINIMAL PROTOBUF PARSER
;
; Returns an object mapping field number to value: a number
; for varint fields, an array of bytes for length-delimited
; fields. Fixed-width fields are skipped.
; ============================================================

ParseS7Proto(Bytes)
{
    Fields := {}

    if !IsObject(Bytes)
        return Fields

    Index := 1
    Count := Bytes.Length()

    while (Index <= Count)
    {
        Key := ReadS7Varint(Bytes, Index)
        Field := Key >> 3
        WireType := Key & 7

        if (WireType = 0)
        {
            Fields[Field] := ReadS7Varint(Bytes, Index)
        }
        else if (WireType = 2)
        {
            Size := ReadS7Varint(Bytes, Index)
            Value := []

            Loop, %Size%
                Value.Push(Bytes[Index + A_Index - 1])

            Index += Size
            Fields[Field] := Value
        }
        else if (WireType = 5)
        {
            Index += 4
        }
        else if (WireType = 1)
        {
            Index += 8
        }
        else
        {
            break
        }
    }

    return Fields
}


ReadS7Varint(Bytes, ByRef Index)
{
    Value := 0
    Shift := 0

    while (Index <= Bytes.Length())
    {
        Byte := Bytes[Index]
        Index += 1

        Value |= (Byte & 0x7F) << Shift

        if !(Byte & 0x80)
            break

        Shift += 7
    }

    return Value
}


GetS7ProtoField(Bytes, Field)
{
    Fields := ParseS7Proto(Bytes)

    return Fields.HasKey(Field) ? Fields[Field] : ""
}


S7BytesToHex(Bytes)
{
    Hex := ""

    for Index, Value in Bytes
    {
        if (Index > 1)
            Hex .= " "

        Hex .= Format("{:02X}", Value)
    }

    return Hex
}


; ============================================================
; S7 - WAIT FOR SOCKET
;
; Mode:
;   1 = readable
;   2 = writable
;
; Uses select() so the socket can never block AHK.
; ============================================================

WaitForS7Socket(Socket, Mode, TimeoutMs)
{
    if (Socket = -1)
        return false

    VarSetCapacity(ReadSet, 512, 0)
    VarSetCapacity(WriteSet, 512, 0)
    VarSetCapacity(ExceptionSet, 512, 0)

    if (Mode = 1)
    {
        NumPut(1, ReadSet, 0, "UInt")
        NumPut(Socket, ReadSet, 8, "Ptr")
    }
    else
    {
        NumPut(1, WriteSet, 0, "UInt")
        NumPut(Socket, WriteSet, 8, "Ptr")
    }

    NumPut(1, ExceptionSet, 0, "UInt")
    NumPut(Socket, ExceptionSet, 8, "Ptr")

    Seconds := Floor(TimeoutMs / 1000)
    Microseconds := Mod(TimeoutMs, 1000) * 1000

    VarSetCapacity(TimeValue, 8, 0)

    NumPut(Seconds, TimeValue, 0, "Int")
    NumPut(Microseconds, TimeValue, 4, "Int")

    Result := DllCall("Ws2_32\select"
        , "Int", 0
        , "Ptr", &ReadSet
        , "Ptr", &WriteSet
        , "Ptr", &ExceptionSet
        , "Ptr", &TimeValue
        , "Int")

    if (Result > 0)
        return true

    if (Result = 0)
    {
        Log("S7 FOCUS: select() timeout. Mode=" . Mode . " Timeout=" . TimeoutMs . "ms")
        return false
    }

    ErrorCode := DllCall("Ws2_32\WSAGetLastError")

    Log("S7 FOCUS: select() failed. Error=" . ErrorCode)

    return false
}


; ============================================================
; S7 - CLOSE FOCUS CONNECTION
;
; Graceful close: tell the camera we are done sending, then
; read and discard anything still arriving (face-tracking
; events) until the camera closes its side. Closing with
; unread data makes Windows send a TCP reset instead.
; ============================================================

CloseS7FocusConnection()
{
    global S7FocusSocket
    global S7CloseTimeoutMs

    if (S7FocusSocket = -1)
        return

    Log("S7 FOCUS: Closing TCP connection")

    ; SD_SEND = 1
    DllCall("Ws2_32\shutdown", "Ptr", S7FocusSocket, "Int", 1)

    VarSetCapacity(Discard, 2048, 0)

    Deadline := A_TickCount + S7CloseTimeoutMs

    Loop
    {
        Remaining := Deadline - A_TickCount

        if (Remaining <= 0)
            break

        if !WaitForS7Socket(S7FocusSocket, 1, Remaining)
            break

        Received := DllCall("Ws2_32\recv"
            , "Ptr", S7FocusSocket
            , "Ptr", &Discard
            , "Int", 2048
            , "Int", 0
            , "Int")

        ; 0 = camera closed its side, < 0 = error.
        if (Received <= 0)
            break
    }

    DllCall("Ws2_32\closesocket", "Ptr", S7FocusSocket)

    S7FocusSocket := -1
}


; ============================================================
; S7 - CLEANUP WINSOCK
; ============================================================

CleanupS7Winsock()
{
    global S7WinsockStarted

    if S7WinsockStarted
    {
        DllCall("Ws2_32\WSACleanup")

        S7WinsockStarted := false

        Log("S7 FOCUS: Winsock cleaned up")
    }
}


; ============================================================
; S7 - FOCUS STATUS TOOLTIP
; ============================================================

ShowFocusStatus(Message, DurationMs := 1000)
{
    ToolTip, %Message%
    SetTimer, RemoveToolTip, % -DurationMs
}


; ============================================================
; S7 - BUFFER TO HEX
; ============================================================

S7BufferToHex(ByRef Buffer, Length)
{
    Hex := ""

    Loop, %Length%
    {
        Value := NumGet(Buffer, A_Index - 1, "UChar")

        if (A_Index > 1)
            Hex .= " "

        Hex .= Format("{:02X}", Value)
    }

    return Hex
}


; ============================================================
; TOOLTIP
; ============================================================

ShowZoom(CameraNum, Pct)
{
    global CameraNames

    Name := CameraNames.HasKey(CameraNum) ? CameraNames[CameraNum] : "Camera"

    ToolTip, %Name% Zoom: %Pct%`%
    SetTimer, RemoveToolTip, -800
}


RemoveToolTip:
    ToolTip
return


; ============================================================
; EXIT CLEANUP
;
; Registered with OnExit at startup.
; ============================================================

WebcamZoomExit(ExitReason, ExitCode)
{
    Log("Webcam Zoom Controller exiting (" . ExitReason . ")")

    CloseS7FocusConnection()
    CleanupS7Winsock()
}


; ============================================================
; LOGGING
; ============================================================

Log(Message)
{
    global LogFolder
    global LogFileName
    global LogOldFileName
    global LogMaxBytes

    static WriteCount := 0

    LogPath := LogFolder . "\" . LogFileName

    ; Check the size on the first write and every 100 after.
    ; Past the limit, the log becomes the .old log (replacing
    ; any previous one) and a new log starts.
    if (Mod(WriteCount, 100) = 0)
    {
        FileGetSize, LogSize, %LogPath%

        if (!ErrorLevel && LogSize > LogMaxBytes)
            FileMove, %LogPath%, %LogFolder%\%LogOldFileName%, 1
    }

    WriteCount += 1

    FormatTime, TimeStamp,, yyyy-MM-dd HH:mm:ss

    FileAppend, %TimeStamp% - %Message%`r`n, %LogPath%
}