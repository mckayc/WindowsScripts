; ---------- Configuration ----------
SetWorkingDir, D:\Backup Files\App Settings\OBS\Plugins
CamParam := ".\CamParam.exe"
TotalCams := 6  ; devices 0 to 5

; Function to zoom all cameras
ZoomAllCams(zoomLevel)
{
    global CamParam, TotalCams
    Loop, % TotalCams
    {
        camID := A_Index - 1
        Run, %CamParam% device %camID% zoom %zoomLevel%,, Hide
    }
}

; ---------- Hotkeys ----------
^Numpad4:: ; Ctrl + Numpad4 -> zoom 50
ZoomAllCams(50)
return

^Numpad9:: ; Ctrl + Numpad9 -> zoom 98
ZoomAllCams(98)
return

; Interpolated hotkeys: 5-8
zoomMin := 50
zoomMax := 98
hotkeyZoomMap := {}
hotkeys := ["^Numpad5", "^Numpad6", "^Numpad7", "^Numpad8"]
count := hotkeys.Length()

Loop, % count
{
    key := hotkeys[A_Index]
    ; Linear interpolation formula
    zoom := Round(zoomMin + ((zoomMax - zoomMin) / (count + 1) * A_Index))
    hotkeyZoomMap[key] := zoom
}

; Bind interpolated hotkeys dynamically
for key, zoom in hotkeyZoomMap
{
    Hotkey, %key%, Func("ZoomAllCams").Bind(zoom)
}
