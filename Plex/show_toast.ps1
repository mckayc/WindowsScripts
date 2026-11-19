# ============================================================
# Show the "now playing" text as a real Windows toast notification,
# with the album art next to the text when it exists.
#
# Called by the AutoHotkey Alt+N hotkey after now_playing.py has run:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden
#       -File show_toast.ps1
#
# It reads, from this script's own folder:
#   now_playing.txt      - line 1 is the title, the rest are body lines
#   now_playing_att.txt  - optional footer line; if it matches the last
#                          line of now_playing.txt, that line is shown as
#                          the toast's small attribution text instead
#   now_playing_art.jpg  - album art (optional; .png also recognised)
#
# Exits 0 on success, 1 on any failure - the AutoHotkey script falls
# back to its plain tray tip if this exits non-zero.
# Note: must run under Windows PowerShell 5.1 (powershell.exe), not
# PowerShell 7 (pwsh) - the toast WinRT types are not available there.
# In the Action Center history the toast appears as coming from
# "Windows PowerShell"; that is normal for this technique.
# ============================================================

$ErrorActionPreference = 'Stop'

try {
    $folder = Split-Path -Parent $MyInvocation.MyCommand.Path
    $textFile = Join-Path $folder 'now_playing.txt'
    $lines = @(Get-Content -LiteralPath $textFile -Encoding UTF8 |
        Where-Object { $_ -ne '' })
    if ($lines.Count -eq 0) { exit 1 }
    $title = $lines[0]
    $body = @()
    if ($lines.Count -gt 1) { $body = $lines[1..($lines.Count - 1)] }

    $att = ''
    $attFile = Join-Path $folder 'now_playing_att.txt'
    if (Test-Path -LiteralPath $attFile) {
        $att = (Get-Content -LiteralPath $attFile -Encoding UTF8 -Raw).Trim()
    }
    if ($att -ne '' -and $body.Count -gt 0 -and $body[$body.Count - 1] -eq $att) {
        if ($body.Count -eq 1) { $body = @() }
        else { $body = $body[0..($body.Count - 2)] }
    }

    $art = $null
    foreach ($name in 'now_playing_art.jpg', 'now_playing_art.png') {
        $candidate = Join-Path $folder $name
        if (Test-Path -LiteralPath $candidate) { $art = $candidate; break }
    }

    function Esc([string]$s) {
        return [System.Security.SecurityElement]::Escape($s)
    }

    $imageXml = ''
    if ($art) {
        $uri = ([System.Uri]$art).AbsoluteUri
        $imageXml = "<image placement=`"appLogoOverride`" hint-crop=`"none`" src=`"$uri`"/>"
    }
    $textXml = "<text hint-maxLines=`"1`">$(Esc $title)</text>"
    foreach ($line in $body) {
        $textXml += "<text>$(Esc $line)</text>"
    }
    if ($att -ne '') {
        $textXml += "<text placement=`"attribution`">$(Esc $att)</text>"
    }
    $toastXml = "<toast duration=`"short`"><visual><binding template=`"ToastGeneric`">$imageXml$textXml</binding></visual></toast>"

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    exit 0
}
catch {
    exit 1
}
