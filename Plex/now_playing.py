"""
What is playing on the Plexamp client right now?

    pythonw now_playing.py     (silent - used by the AutoHotkey hotkey)
    python  now_playing.py     (also prints the result)

It asks the Plex server for its current sessions, finds the one belonging
to the client named in config.json, looks up the track's own metadata
(play count, last played, release date), and writes the result to
now_playing.txt in this folder, e.g.:

    Carrying the Banner
    Newsies Original Broadway Cast
    Newsies (Original Broadway Cast Recording)
    ★★★★★ 5 stars · 1:23 / 3:45 · 2:22 left · Playing
    FLAC · 1,411 kbps
    Played 12x · last played Nov 3, 2026 · Released Mar 27, 2012

The last line is also written on its own to now_playing_att.txt -
show_toast.ps1 renders it as the toast's small attribution footer.

It also downloads the track's album art to now_playing_art.jpg (or .png)
in this folder. The AutoHotkey hotkey (Alt+N) runs this, then runs
show_toast.ps1, which shows a real Windows toast notification with the
album art next to the text - Plexamp itself never comes to the front.
"""

import json
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree

import requests

HERE = Path(__file__).resolve().parent
CONFIG_PATH = HERE / "config.json"
OUT_PATH = HERE / "now_playing.txt"
ATT_PATH = HERE / "now_playing_att.txt"


def fmt_time(ms) -> str:
    try:
        total = int(float(ms)) // 1000
    except (TypeError, ValueError):
        return "?"
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def fmt_date(dt: datetime) -> str:
    """'Nov 3, 2026' - built manually so it works the same on Windows."""
    return f"{dt:%b} {dt.day}, {dt.year}"


def star_text(user_rating) -> str:
    """'★★★★☆ 4.5 stars' for a Plex userRating (0-10), or '☆☆☆☆☆ Not rated'."""
    try:
        rating = float(user_rating or 0)
    except (TypeError, ValueError):
        rating = 0
    if rating <= 0:
        return "☆☆☆☆☆ Not rated"
    stars = rating / 2  # Plex stores ratings 0-10, stars are 0-5
    full = max(0, min(5, int(stars + 0.5)))
    glyphs = "★" * full + "☆" * (5 - full)
    return f"{glyphs} {stars:g} star" + ("s" if stars != 1 else "")


def find_session(root, client_name: str):
    """Return (track_element, player_element) for client_name, or None."""
    matches = []
    for track in root:
        player = track.find("Player")
        if player is None:
            continue
        title = player.attrib.get("title", "")
        product = player.attrib.get("product", "")
        if title == client_name or (not client_name and product == "Plexamp"):
            matches.append((track, player))
    if not matches:
        return None
    # Prefer a session that is actually playing over a paused one.
    matches.sort(key=lambda mp: 0 if mp[1].attrib.get("state") == "playing" else 1)
    return matches[0]


def format_now_playing(track, player, meta):
    """Build (lines, attribution, thumb_path) from session + metadata elements.

    meta is the track's /library/metadata element, or None if the lookup
    failed - the play-count / release-date bits are then simply omitted.
    """
    a = track.attrib
    m = meta.attrib if meta is not None else {}
    # Album art: the album's thumb if the session has it, else the track's.
    thumb = a.get("parentThumb") or a.get("thumb")

    # Release date (full) from the track metadata, if Plex has one.
    release = None
    raw_release = m.get("originallyAvailableAt")
    if raw_release:
        try:
            release = fmt_date(datetime.strptime(raw_release, "%Y-%m-%d"))
        except ValueError:
            release = raw_release

    lines = [a.get("title", "Unknown track")]
    if a.get("grandparentTitle"):
        lines.append(a["grandparentTitle"])  # artist
    if a.get("parentTitle"):
        album = a["parentTitle"]
        # Year after the album - unless the full release date is shown
        # below anyway, in which case the year would just duplicate it.
        year = a.get("parentYear") or a.get("year")
        if year and not release:
            album += f" ({year})"
        lines.append(album)

    # Rating first on this line - the toast popup only shows the first
    # few lines, so the important things go first, not at the end.
    bits = [star_text(a.get("userRating") or m.get("userRating"))]
    duration, offset = a.get("duration"), a.get("viewOffset")
    if duration is not None and offset is not None:
        bits.append(f"{fmt_time(offset)} / {fmt_time(duration)}")
        try:
            remaining = max(0, int(float(duration)) - int(float(offset)))
            bits.append(f"{fmt_time(remaining)} left")
        except (TypeError, ValueError):
            pass
    state = player.attrib.get("state", "")
    if state:
        bits.append(state.capitalize())
    lines.append(" · ".join(bits))

    # Audio quality, from the session's Media element.
    media = track.find("Media")
    if media is not None:
        codec = (media.attrib.get("audioCodec") or "").upper()
        bitrate = media.attrib.get("bitrate")
        quality = []
        if codec:
            quality.append(codec)
        if bitrate:
            try:
                quality.append(f"{int(bitrate):,} kbps")
            except ValueError:
                quality.append(f"{bitrate} kbps")
        if quality:
            lines.append(" · ".join(quality))

    # Attribution footer: play count / last played / release date.
    att_bits = []
    if meta is not None:
        try:
            plays = int(m.get("viewCount") or 0)
        except ValueError:
            plays = 0
        if plays > 0:
            att_bits.append(f"Played {plays}x")
            last = m.get("lastViewedAt")
            if last:
                try:
                    att_bits.append(
                        "last played " + fmt_date(datetime.fromtimestamp(int(last)))
                    )
                except (ValueError, OSError, OverflowError):
                    pass
        else:
            att_bits.append("First play")
    if release:
        att_bits.append(f"Released {release}")
    attribution = " · ".join(att_bits)
    return lines, attribution, thumb


def fetch_art(plex_url: str, token: str, thumb: str | None) -> Path | None:
    """Download the album art to now_playing_art.jpg/.png next to this script.

    Removes any stale art file first, so an old album's art can never show
    up under a new track. Returns the saved path, or None if no art.
    """
    art_jpg = HERE / "now_playing_art.jpg"
    art_png = HERE / "now_playing_art.png"
    for p in (art_jpg, art_png):
        try:
            p.unlink(missing_ok=True)
        except OSError:
            pass
    if not thumb:
        return None
    try:
        r = requests.get(
            f"{plex_url}{thumb}",
            headers={"X-Plex-Token": token},
            timeout=10,
        )
        r.raise_for_status()
        data = r.content
    except Exception:  # noqa: BLE001 - art is optional; text still shows
        return None
    if not data:
        return None
    target = art_png if data[:4] == b"\x89PNG" else art_jpg
    target.write_bytes(data)
    return target


def fetch_metadata(plex_url: str, token: str, rating_key):
    """The track's own /library/metadata element, or None on any failure."""
    if not rating_key:
        return None
    try:
        r = requests.get(
            f"{plex_url}/library/metadata/{rating_key}",
            headers={"X-Plex-Token": token, "Accept": "application/xml"},
            timeout=10,
        )
        r.raise_for_status()
        root = ElementTree.fromstring(r.content)
        return root[0] if len(root) else None
    except Exception:  # noqa: BLE001 - extra info only; the toast still works
        return None


def main() -> None:
    attribution = ""
    try:
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        plex_url = str(config.get("plex_url", "")).rstrip("/")
        token = str(config.get("plex_token", "")).strip()
        client_name = str(config.get("client_name", "")).strip()
        headers = {"X-Plex-Token": token, "Accept": "application/xml"}
        r = requests.get(f"{plex_url}/status/sessions", headers=headers, timeout=10)
        r.raise_for_status()
        found = find_session(ElementTree.fromstring(r.content), client_name)
        if found is None:
            lines = [f"Nothing is playing on {client_name or 'Plexamp'} right now."]
            fetch_art(plex_url, token, None)
        else:
            track, player = found
            meta = fetch_metadata(plex_url, token, track.attrib.get("ratingKey"))
            lines, attribution, thumb = format_now_playing(track, player, meta)
            fetch_art(plex_url, token, thumb)
    except Exception as exc:  # noqa: BLE001 - the notification should say what went wrong
        lines = [f"Could not check what is playing:\n{exc}"]
        fetch_art("", "", None)  # clear any stale art
    text = "\n".join(lines + ([attribution] if attribution else []))
    OUT_PATH.write_text(text + "\n", encoding="utf-8")
    ATT_PATH.write_text(attribution + "\n" if attribution else "", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
