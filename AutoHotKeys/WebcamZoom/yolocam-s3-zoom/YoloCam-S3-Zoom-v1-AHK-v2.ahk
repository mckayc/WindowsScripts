#Requires AutoHotkey v2.0
#SingleInstance Force

exe := A_ScriptDir "\yolocam-s3-zoom.exe"

; Change these hotkeys if desired.
F9::RunWait('"' exe '" out 0.25',, 'Hide')
F10::RunWait('"' exe '" in 0.25',, 'Hide')
F11::RunWait('"' exe '" reset',, 'Hide')

; Optional: uncomment these if you want fixed zoom presets.
; F7::RunWait('"' exe '" set 1.0',, 'Hide')
; F8::RunWait('"' exe '" set 2.0',, 'Hide')
