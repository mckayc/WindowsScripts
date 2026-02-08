# Webcam Zoom Controller

An AutoHotkey script to manage digital zoom for multiple webcams simultaneously or individually using the `CamParam.exe` command-line utility.

## Features
- **Auto-Sync:** On startup, the script detects your cameras' hardware zoom levels and calibrates the percentage.
- **Interpolation:** Maps a simple 0-100% zoom scale to the specific hardware limits of each camera.
- **Auto-Download:** Automatically fetches `CamParam.exe` if it's missing from the directory.
- **Multi-Camera Support:** Supports up to 3 cameras with unique serial number tracking.

## Hotkeys

| Action | Hotkey |
| :--- | :--- |
| **Global Zoom In** | `Ctrl` + `Win` + `=` |
| **Global Zoom Out** | `Ctrl` + `Win` + `-` |
| **Talking Head In/Out** | `Ctrl` + `Win` + `1` / `Q` |
| **Overhead Cam In/Out** | `Ctrl` + `Win` + `2` / `W` |
| **Side Cam In/Out** | `Ctrl` + `Win` + `3` / `E` |
| **Re-sync Hardware** | `Ctrl` + `Win` + `R` |

## Setup
1. Download `WebcamZoom.ahk`.
2. Ensure you have [AutoHotkey](https://www.autohotkey.com/) installed.
3. Edit the `global C#_SN` variables in the script with your camera serial numbers (found by running `CamParam.exe` in a terminal).
4. Run the script.

## Dependencies
- This script relies on [CamParam](https://github.com/scottgarner/CamParam). The executable will be downloaded automatically on first run.

## Troubleshooting
Check the `logs/webcamzoom.log` file for detailed execution steps and error reporting. If a camera is not found, ensure it is plugged in and recognized by Windows, then press `Ctrl+Win+R` to refresh.