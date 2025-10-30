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

; ---------- Hotkeys: Ctrl + Win + Numpad4–9 (50–74) ----------
^#Numpad4::ZoomAllCams(50)
^#Numpad5::ZoomAllCams(55)
^#Numpad6::ZoomAllCams(60)
^#Numpad7::ZoomAllCams(65)
^#Numpad8::ZoomAllCams(70)
^#Numpad9::ZoomAllCams(74)

; ---------- Hotkeys: Ctrl + Alt + Numpad4–9 (75–98) ----------
^!Numpad4::ZoomAllCams(75)
^!Numpad5::ZoomAllCams(80)
^!Numpad6::ZoomAllCams(85)
^!Numpad7::ZoomAllCams(90)
^!Numpad8::ZoomAllCams(95)
^!Numpad9::ZoomAllCams(98)
