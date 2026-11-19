"""
Play a named Plex playlist on a named Plexamp client.

Usage:
    python  play_playlist.py "5 Stars"
    pythonw play_playlist.py "Not Rated"      (silent, used by AutoHotkey)

All settings live in config.json in this same folder:
    plex_url     e.g. "http://192.168.1.10:32400"  (or http://127.0.0.1:32400
                 if the Plex server runs on this same PC)
    plex_token   your X-Plex-Token - keep this file private, never share it
    client_name  exact Plexamp client name - run list_plex.py to see it
    shuffle      true / false

Every run (success or failure) appends one line to play_playlist.log in this
same folder, so a silent pythonw launch that does nothing can be diagnosed.
Requires:  pip install plexapi   (run once:  py -m pip install plexapi)
"""

import json
import sys
import traceback
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG_PATH = HERE / "config.json"
LOG_PATH = HERE / "play_playlist.log"


def log(message: str) -> None:
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with LOG_PATH.open("a", encoding="utf-8") as fh:
            fh.write(f"[{stamp}] {message}\n")
    except OSError:
        pass


def fail(message: str) -> "SystemExit":
    log(f"ERROR: {message}")
    print(f"ERROR: {message}", file=sys.stderr)
    return SystemExit(1)


def main() -> int:
    if len(sys.argv) < 2:
        raise fail('No playlist name given. Example: play_playlist.py "5 Stars"')

    playlist_name = sys.argv[1]
    shuffle_flag = "--shuffle" in sys.argv[2:]

    # --- config -------------------------------------------------------------
    try:
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise fail(f"config.json not found next to this script: {CONFIG_PATH}")
    except json.JSONDecodeError as exc:
        raise fail(f"config.json is not valid JSON: {exc}")

    plex_url = str(config.get("plex_url", "")).strip()
    plex_token = str(config.get("plex_token", "")).strip()
    client_name = str(config.get("client_name", "")).strip()
    client_url = str(config.get("client_url", "")).strip()
    shuffle = bool(config.get("shuffle", False)) or shuffle_flag

    if "PASTE_" in plex_token or not plex_token:
        raise fail("plex_token is still the placeholder in config.json - paste your real token in.")
    if "PASTE_" in client_name or not client_name:
        raise fail("client_name is still the placeholder in config.json - run list_plex.py and copy the exact name in.")
    if not plex_url.startswith("http"):
        raise fail(f"plex_url in config.json doesn't look right: {plex_url!r}")

    # --- connect ------------------------------------------------------------
    try:
        from plexapi.server import PlexServer
    except ImportError:
        raise fail("plexapi is not installed. Run once:  py -m pip install plexapi")

    try:
        plex = PlexServer(plex_url, plex_token)
    except Exception as exc:  # noqa: BLE001 - report anything Plex throws at us
        raise fail(f"Could not connect to Plex server at {plex_url}: {exc}")

    # --- find client + playlist ---------------------------------------------
    # If config.json sets client_url (diagnose_plex.py finds it), connect to
    # the player at that exact address instead of trusting the address the
    # server has on file - on McKay's setup the server's record pointed at
    # the server's own IP :32500, where nothing listens.
    client = None
    if client_url:
        try:
            from plexapi.client import PlexClient

            client = PlexClient(baseurl=client_url, server=plex, token=plex_token)
            log(f"Connected to client directly at client_url={client_url}: {client.title!r}")
            if client_name and client.title and client.title != client_name:
                log(f"NOTE: client at {client_url} calls itself {client.title!r}, config client_name is {client_name!r}")
        except Exception as exc:  # noqa: BLE001
            log(f"client_url connection failed ({exc}); falling back to server lookup by name")
            client = None
    if client is None:
        try:
            client = plex.client(client_name)
        except Exception as exc:  # noqa: BLE001
            try:
                available = ", ".join(sorted(c.title for c in plex.clients())) or "(none)"
            except Exception:  # noqa: BLE001
                available = "(could not list clients)"
            raise fail(
                f"Plexamp client {client_name!r} not found / not reachable: {exc}. "
                f"Clients the server can see right now: {available}. "
                "Make sure Plexamp is running, then run list_plex.py again."
            )

    try:
        playlist = plex.playlist(playlist_name)
    except Exception as exc:  # noqa: BLE001
        try:
            available = ", ".join(sorted(p.title for p in plex.playlists())) or "(none)"
        except Exception:  # noqa: BLE001
            available = "(could not list playlists)"
        raise fail(
            f"Playlist {playlist_name!r} not found: {exc}. "
            f"Playlists on this server: {available}"
        )

    # --- play ---------------------------------------------------------------
    # Log where the server thinks this client lives - this is the detail
    # that diagnosed the first failure (server had the client at
    # 192.168.1.111:32500, i.e. the server's own IP, and nothing was
    # listening there, so the direct connection was refused).
    try:
        log(
            f"Client {client_name!r}: address={getattr(client, 'address', '?')} "
            f"port={getattr(client, 'port', '?')} "
            f"baseurl={getattr(client, '_baseurl', '?')} "
            f"machineIdentifier={getattr(client, 'machineIdentifier', '?')}"
        )
    except Exception:  # noqa: BLE001
        pass

    # Try, in order:
    #   1. Proxy through the server, with a play queue built from the playlist
    #   2. Proxy through the server, playlist directly
    #   3. Direct to the client, with a play queue
    #   4. Direct to the client, playlist directly
    # The proxy routes send the command to the server (:32400), which relays
    # it to the client over the connection the client already has open -
    # they never dial the client's advertised companion address directly,
    # so they work even when that address is wrong or unreachable.
    errors: list[str] = []

    def attempt(label: str, use_queue: bool) -> bool:
        try:
            if use_queue:
                queue = plex.createPlayQueue(playlist, shuffle=1 if shuffle else 0)
                client.playMedia(queue)
            else:
                client.playMedia(playlist, shuffle=1 if shuffle else 0)
            log(f"OK ({label}): {playlist_name!r} -> {client_name!r} shuffle={shuffle}")
            print(f"OK ({label}): {playlist_name!r} -> {client_name!r}")
            return True
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{label}: {exc}")
            log(f"FAILED ({label}): {exc}")
            return False

    # If we connected via a known-good client_url, go direct first - the
    # proxy route is the one the server's bad client record breaks.
    # Otherwise try proxy first, then direct.
    proxy_order = (False, True) if client_url else (True, False)
    for proxy in proxy_order:
        try:
            client.proxyThroughServer(proxy)
        except Exception as exc:  # noqa: BLE001
            log(f"proxyThroughServer({proxy}) not available: {exc}")
            if proxy:
                continue
        mode = "proxy" if proxy else "direct"
        if attempt(f"{mode} + play queue", use_queue=True):
            return 0
        if attempt(f"{mode} + playlist", use_queue=False):
            return 0

    log("ERROR: all play routes failed:\n" + "\n".join(errors) + "\n" + traceback.format_exc())
    raise fail("All play routes failed - see play_playlist.log. " + " | ".join(errors))


if __name__ == "__main__":
    raise SystemExit(main())
