YOLOCAM S3 DIRECT EPTZ ZOOM - TEST BUILD
========================================

This is an experimental Windows helper for the YoloCam S3. It bypasses
YoloLiv Compose and talks directly to the camera's USB network control
interface using the reverse-engineered ePTZ protocol.

IMPORTANT
---------
1. Close YoloLiv Compose before testing. The reverse-engineered client
   documentation reports that the camera does not handle two simultaneous
   control connections reliably.
2. Connect the S3 directly to the Windows PC by USB.
3. Verify that Windows can reach the camera at:
       192.168.123.10
   You can test with:
       ping 192.168.123.10
4. Start with:
       yolocam-s3-zoom.exe get
   A successful result looks like:
       1.00 0.500 0.500
5. Then try:
       yolocam-s3-zoom.exe set 2.0
   The camera should move to 2x centered ePTZ.
6. Then try:
       yolocam-s3-zoom.exe reset

COMMANDS
--------
get
    Reads the current ePTZ zoom and center.

set <factor> [centerX] [centerY]
    Sets zoom directly. Factor is 1.0 through 4.0.
    Center coordinates are normalized 0.0 through 1.0.
    Example:
       yolocam-s3-zoom.exe set 2.0

in [step]
    Reads current zoom and increases it. Default step is 0.25.
    Example:
       yolocam-s3-zoom.exe in 0.25

out [step]
    Reads current zoom and decreases it. Default step is 0.25.

reset
    Sets centered zoom to 1.0x.

AUTOHOTKEY
----------
Two example scripts are included:
    YoloCam-S3-Zoom-v1-AHK-v2.ahk
    YoloCam-S3-Zoom-v1-AHK-v1.ahk

Default keys:
    F9  zoom out 0.25x
    F10 zoom in  0.25x
    F11 reset to 1.0x

These keys can be changed to anything you prefer.

NOTES
-----
The helper is intentionally a small native Windows executable with no
Python/Go installation required on the target PC.

This build has NOT been physically tested against an S3 in this environment.
The first test should therefore be the harmless 'get' command.

Protocol basis:
- YoloCam S3 exposes a CDC NCM USB network interface.
- Camera control uses TCP port 12345.
- ePTZ is Property ID 117.
- Zoom is represented by ZoomRect with zoom_factor 1.0 through 4.0.
- A session attach is sent before control commands.
