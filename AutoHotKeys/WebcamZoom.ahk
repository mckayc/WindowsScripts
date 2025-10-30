; ===============================
; Webcam Zoom Controller - AutoHotkey
; ===============================

; ---------- Set working directory ----------
SetWorkingDir, D:\Backup Files\App Settings\OBS\Webcam Plugins

TotalCams := 6  ; devices 0 to 5

; ---------- Function to zoom all cameras ----------
ZoomAllCams(zoomLevel)
{
    global TotalCams
    Loop, %TotalCams%
    {
        camID := A_Index - 1
        ; Run CamParam.exe for each camera via cmd to handle spaces
        Run, %ComSpec% /c ""%A_WorkingDir%\CamParam.exe" device %camID% zoom %zoomLevel%"",, Hide
    }
    ; Show tooltip as feedback
    ToolTip, Zoom command sent to %TotalCams% cameras at %zoomLevel%
    Sleep, 1000
    ToolTip
}

; ---------- Hotkeys with corrected zoom levels ----------
^Numpad4::ZoomAllCams(50)  ; Ctrl+Numpad4
^Numpad5::ZoomAllCams(60)  ; Ctrl+Numpad5
^Numpad6::ZoomAllCams(70)  ; Ctrl+Numpad6
^Numpad7::ZoomAllCams(80)  ; Ctrl+Numpad7
^Numpad8::ZoomAllCams(90)  ; Ctrl+Numpad8
^Numpad9::ZoomAllCams(98)  ; Ctrl+Numpad9
