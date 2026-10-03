#Requires AutoHotkey v1.1.36+
#NoEnv
#SingleInstance Force
#UseHook On
SendMode Input
SetWorkingDir %A_ScriptDir%

; ============================================================
; YoloCam S3 + Yololiv S7 Zoom + Focus Controller
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


; ============================================================
; S7 FOCUS NETWORK SETTINGS
; ============================================================

global S7FocusIP := "192.168.127.10"
global S7FocusPort := 12345

; Captured application protocol uses an incrementing
; transaction counter.
global S7FocusCounter := 0x31

; Persistent TCP socket.
global S7FocusSocket := -1

; Winsock initialization state.
global S7WinsockStarted := false

; Prevent overlapping focus commands.
global S7FocusBusy := false

; Focus networking timeouts.
global S7ConnectTimeoutMs := 1000
global S7SendTimeoutMs := 500
global S7ReceiveTimeoutMs := 500

; select() polling interval.
global S7PollIntervalMs := 10


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
Log("S7 Focus Counter: " . Format("{:02X}", S7FocusCounter))
Log("========================================")

InitializeCameras()

return


; ============================================================
; HOTKEYS
; ============================================================


; ============================================================
; CAMERA 1 - TALKING HEAD
; ============================================================

^#1::
    Log("HOTKEY: Ctrl+Win+1")
    AdjustS3(1, 1)
return

^#q::
    Log("HOTKEY: Ctrl+Win+Q")
    AdjustS3(1, -1)
return


; ============================================================
; CAMERA 2 - OVERHEAD
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
; CAMERA 3 - SIDE
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
; CAMERA 4 - YOLOLIV S7 ZOOM
; ============================================================

^#4::
    Log("HOTKEY: Ctrl+Win+4")
    AdjustS7(1)
return

^#d::
    Log("HOTKEY: Ctrl+Win+D")
    AdjustS7(-1)
return


; ============================================================
; S7 FOCUS
; ============================================================

^#f::
    Log("HOTKEY: Ctrl+Win+F")
    S7FaceFocus()
return

^#a::
    Log("HOTKEY: Ctrl+Win+A")
    S7AutoFocusCenter()
return


; ============================================================
; ALL CAMERAS - ZOOM IN
; ============================================================

^#=::
    Log("HOTKEY: Ctrl+Win+=")
    AdjustS3(1, 1)
    AdjustS3(2, 1)
    AdjustS3(3, 1)
    AdjustS7(1)
return


; ============================================================
; ALL CAMERAS - ZOOM OUT
; ============================================================

^#-::
    Log("HOTKEY: Ctrl+Win+-")
    AdjustS3(1, -1)
    AdjustS3(2, -1)
    AdjustS3(3, -1)
    AdjustS7(-1)
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
    ; 04 = Face Focus
    SendS7FocusCommand(4, "Face Focus")
}


; ============================================================
; S7 - AUTO FOCUS CENTER
; ============================================================

S7AutoFocusCenter()
{
    ; 03 = Auto-Focus Center
    SendS7FocusCommand(3, "Auto-Focus Center")
}


; ============================================================
; S7 - SEND FOCUS COMMAND
; ============================================================

SendS7FocusCommand(Mode, Description)
{
    global S7FocusCounter
    global S7FocusBusy

    ; Prevent multiple focus commands from overlapping.
    if (S7FocusBusy)
    {
        Log("S7 FOCUS: Command ignored because another focus command is active")
        return false
    }

    S7FocusBusy := true

    Log("----------------------------------------")
    Log("S7 FOCUS: " . Description)
    Log("S7 FOCUS counter: " . Format("{:02X}", S7FocusCounter))
    Log("S7 FOCUS mode: " . Mode)

    if !EnsureS7FocusConnection()
    {
        Log("S7 FOCUS FAILED: Could not establish TCP connection")
        ShowFocusStatus("S7 Focus: CONNECTION FAILED")
        S7FocusBusy := false
        return false
    }

    ; ========================================================
    ; Build the 26-byte focus packet.
    ;
    ; Captured format:
    ;
    ; 08 01 00 00 12 00 00 00
    ; A5 00 00 00
    ; 0A AF
    ; 08 02
    ; 10 COUNTER
    ; 28 17
    ; 32 02
    ; 08 MODE
    ; CHECKSUM
    ; 5A
    ; ========================================================

    Counter := S7FocusCounter & 0xFF

    ; Checksum observed in capture:
    ;
    ; checksum = counter XOR mode XOR 1D

    Checksum := Counter ^ Mode ^ 0x1D

    VarSetCapacity(Packet, 26, 0)

    NumPut(0x08, Packet,  0, "UChar")
    NumPut(0x01, Packet,  1, "UChar")
    NumPut(0x00, Packet,  2, "UChar")
    NumPut(0x00, Packet,  3, "UChar")

    NumPut(0x12, Packet,  4, "UChar")
    NumPut(0x00, Packet,  5, "UChar")
    NumPut(0x00, Packet,  6, "UChar")
    NumPut(0x00, Packet,  7, "UChar")

    NumPut(0xA5, Packet,  8, "UChar")
    NumPut(0x00, Packet,  9, "UChar")
    NumPut(0x00, Packet, 10, "UChar")
    NumPut(0x00, Packet, 11, "UChar")

    NumPut(0x0A, Packet, 12, "UChar")
    NumPut(0xAF, Packet, 13, "UChar")

    NumPut(0x08, Packet, 14, "UChar")
    NumPut(0x02, Packet, 15, "UChar")

    NumPut(0x10, Packet, 16, "UChar")
    NumPut(Counter, Packet, 17, "UChar")

    NumPut(0x28, Packet, 18, "UChar")
    NumPut(0x17, Packet, 19, "UChar")

    NumPut(0x32, Packet, 20, "UChar")
    NumPut(0x02, Packet, 21, "UChar")

    NumPut(0x08, Packet, 22, "UChar")
    NumPut(Mode,  Packet, 23, "UChar")

    NumPut(Checksum, Packet, 24, "UChar")
    NumPut(0x5A, Packet, 25, "UChar")

    Hex := S7BufferToHex(Packet, 26)

    Log("S7 FOCUS TX: " . Hex)

    ; ========================================================
    ; Send 26-byte command.
    ; ========================================================

    Sent := SendS7FocusData(Packet, 26)

    if (Sent != 26)
    {
        ErrorCode := DllCall("Ws2_32\WSAGetLastError")

        Log("S7 FOCUS SEND FAILED. Sent=" . Sent . " Error=" . ErrorCode)

        CloseS7FocusConnection()

        ShowFocusStatus("S7 Focus: SEND FAILED")

        S7FocusBusy := false

        return false
    }

    Log("S7 FOCUS TX OK: 26 bytes")

    ; ========================================================
    ; Read the camera response.
    ;
    ; This is now non-blocking. It can never hang AHK.
    ; ========================================================

    ReceiveS7FocusResponse()

    ; Increment the application transaction counter.
    ; Keep this sequencing unchanged.
    S7FocusCounter := (S7FocusCounter + 1) & 0xFF

    Log("S7 FOCUS next counter: " . Format("{:02X}", S7FocusCounter))
    Log("----------------------------------------")

    ShowFocusStatus("S7 Focus: " . Description)

    S7FocusBusy := false

    return true
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

    Log("S7 FOCUS: Opening persistent TCP connection")

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

    ; WSAEWOULDBLOCK / WSAEINPROGRESS / WSAEALREADY are normal
    ; for a non-blocking connect.
    if (ErrorCode != 10035 && ErrorCode != 10036 && ErrorCode != 10037)
    {
        Log("S7 FOCUS: connect() failed: " . ErrorCode)

        DllCall("Ws2_32\closesocket", "Ptr", Socket)

        return false
    }

    Log("S7 FOCUS: Connect in progress")

    ; --------------------------------------------------------
    ; Wait for connection to complete using select().
    ; --------------------------------------------------------

    if !WaitForS7Socket(Socket, 1, S7ConnectTimeoutMs)
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
; S7 - RECEIVE FOCUS RESPONSE
; ============================================================

ReceiveS7FocusResponse()
{
    global S7FocusSocket
    global S7ReceiveTimeoutMs

    VarSetCapacity(Response, 512, 0)

    ; --------------------------------------------------------
    ; Wait until data is actually available.
    ;
    ; This prevents recv() from ever blocking.
    ; --------------------------------------------------------

    if !WaitForS7Socket(S7FocusSocket, 1, S7ReceiveTimeoutMs)
    {
        Log("S7 FOCUS RX: Receive timeout - no response from camera")

        return false
    }

    Received := DllCall("Ws2_32\recv"
        , "Ptr", S7FocusSocket
        , "Ptr", &Response
        , "Int", 512
        , "Int", 0
        , "Int")

    if (Received > 0)
    {
        Hex := S7BufferToHex(Response, Received)

        Log("S7 FOCUS RX (" . Received . " bytes): " . Hex)

        return true
    }

    if (Received = 0)
    {
        Log("S7 FOCUS RX: Camera closed TCP connection")

        CloseS7FocusConnection()

        return false
    }

    ErrorCode := DllCall("Ws2_32\WSAGetLastError")

    Log("S7 FOCUS RX: recv() error " . ErrorCode)

    return false
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

    ; fd_set structure on 64-bit Windows:
    ; u_int fd_count
    ; SOCKET fd_array[64]
    ;
    ; SOCKET is 64-bit on Win64.

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

    VarSetCapacity(TimeValue, 16, 0)

    NumPut(Seconds, TimeValue, 0, "Int")
    NumPut(Microseconds, TimeValue, 8, "Int")

    Result := DllCall("Ws2_32\select"
        , "Int", 0
        , "Ptr", &ReadSet
        , "Ptr", &WriteSet
        , "Ptr", &ExceptionSet
        , "Ptr", &TimeValue
        , "Int")

    return (Result > 0)
}


; ============================================================
; S7 - CLOSE FOCUS CONNECTION
; ============================================================

CloseS7FocusConnection()
{
    global S7FocusSocket

    if (S7FocusSocket != -1)
    {
        Log("S7 FOCUS: Closing TCP connection")

        DllCall("Ws2_32\closesocket", "Ptr", S7FocusSocket)

        S7FocusSocket := -1
    }
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

ShowFocusStatus(Message)
{
    ToolTip, %Message%
    SetTimer, RemoveToolTip, -1000
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
; EXIT CLEANUP
; ============================================================

WebcamZoomExit:
    Log("Webcam Zoom Controller exiting")

    CloseS7FocusConnection()
    CleanupS7Winsock()

    ExitApp
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