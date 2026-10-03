YOLOCAM ZOOM CONTROLLER V3
==========================

This version controls three YoloCam S3 cameras directly over their USB
network control interfaces and keeps CamParam.exe only for the YoloLiv S7.

CAMERA NETWORKS
---------------
Talking Head: 192.168.124.10 (PC: 192.168.124.11 / Ethernet 3)
Overhead:     192.168.123.10 (PC: 192.168.123.11 / Ethernet 5)
Side:         192.168.127.10 (PC: 192.168.127.11 / Ethernet 7)

The helper binds to the corresponding PC IP for these three cameras so
Windows does not choose the wrong USB network adapter.

FILES
-----
yolocam-s3-zoom-multi.exe   Direct S3 ePTZ helper
YoloCam-Zoom-AHK-v3.ahk     AutoHotkey v1 controller
CamParam.exe                Automatically downloaded for the S7 if absent

HOTKEYS
-------
Ctrl+Win+1  Talking Head zoom in
Ctrl+Win+Q  Talking Head zoom out
Ctrl+Win+2  Overhead zoom in
Ctrl+Win+W  Overhead zoom out
Ctrl+Win+3  Side zoom in
Ctrl+Win+E  Side zoom out
Ctrl+Win+4  YoloLiv S7 zoom in
Ctrl+Win+D  YoloLiv S7 zoom out
Ctrl+Win+=  All cameras zoom in
Ctrl+Win+-  All cameras zoom out
Ctrl+Win+R  Re-sync all cameras

S3 ZOOM SCALE
-------------
The AutoHotkey script preserves the existing 0%-100% user-facing scale.
0% = 1.0x native S3 ePTZ zoom
100% = 4.0x native S3 ePTZ zoom

TESTING
-------
Close YoloLiv Compose before testing the S3 helper. The reverse-engineered
protocol documentation indicates the camera does not reliably handle two
simultaneous control connections.

First test each camera manually:
  yolocam-s3-zoom-multi.exe 192.168.124.10 get
  yolocam-s3-zoom-multi.exe 192.168.123.10 get
  yolocam-s3-zoom-multi.exe 192.168.127.10 get

Expected output is similar to:
  1.00 0.500 0.500

Then test a harmless reset:
  yolocam-s3-zoom-multi.exe 192.168.124.10 reset

AUTOHOTKEY
----------
Run YoloCam-Zoom-AHK-v3.ahk with AutoHotkey v1.1. It should be placed in
the same folder as yolocam-s3-zoom-multi.exe.

CamParam.exe is still used only for the YoloLiv S7.
