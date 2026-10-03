#NoEnv
#SingleInstance Force
SendMode Input
SetWorkingDir %A_ScriptDir%

yoloExe := A_ScriptDir . "\yolocam-s3-zoom.exe"

; Change these hotkeys if desired.
F9::RunWait, % "\"" yoloExe "\" out 0.25",, Hide
F10::RunWait, % "\"" yoloExe "\" in 0.25",, Hide
F11::RunWait, % "\"" yoloExe "\" reset",, Hide

; Optional fixed zoom presets:
; F7::RunWait, % "\"" yoloExe "\" set 1.0",, Hide
; F8::RunWait, % "\"" yoloExe "\" set 2.0",, Hide
