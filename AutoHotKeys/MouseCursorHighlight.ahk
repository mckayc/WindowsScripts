#NoEnv
#SingleInstance Force
SetBatchLines, -1
CoordMode, Mouse, Screen

; =============================
; SETTINGS
; =============================
circleSize := 80        ; Diameter of circle
color := "FFFF00"       ; Yellow
opacity := 160          ; 0–255

toggle := false

; =============================
; HOTKEY TOGGLE
; Ctrl + Shift + Alt + H
; =============================
^+!h::
toggle := !toggle
if (toggle)
{
    CreateHighlight()
    SetTimer, FollowMouse, 10
}
else
{
    SetTimer, FollowMouse, Off
    Gui, Highlight:Destroy
}
return

; =============================
; CREATE HIGHLIGHT GUI
; =============================
CreateHighlight()
{
    global circleSize, color, opacity
    Gui, Highlight:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +LastFound
    Gui, Highlight:Color, %color%
    WinSet, Transparent, %opacity%
    Gui, Highlight:Show, w%circleSize% h%circleSize% NoActivate
    WinSet, Region, 0-0 w%circleSize% h%circleSize% E
}

; =============================
; FOLLOW MOUSE
; =============================
FollowMouse:
MouseGetPos, mx, my
x := mx - (circleSize // 2)
y := my - (circleSize // 2)
Gui, Highlight:Show, x%x% y%y% NoActivate
return