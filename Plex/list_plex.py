"""
Discovery / setup check for the Plex playlist hotkeys.

Run this ONCE before using play_playlist.py:
    python list_plex.py
    (or double-click check_setup.bat)

It connects with the plex_url + plex_token from config.json and prints:
  * the server it found
  * every client the server can see right now - copy the Plexamp one
    EXACTLY into "client_name" in config.json
  * every playlist on the server - check "5 Stars" and "Not Rated"
    appear exactly as spelled there

It also writes the same output to list_plex_output.txt in this folder.
Share THAT file (or a screenshot of the output) if you need help -
it contains no token. Never share config.json.
"""

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG_PATH = HERE / "config.json"
OUT_PATH = HERE / "list_plex_output.txt"

lines: list[str] = []


def out(text: str = "") -> None:
    print(text)
    lines.append(text)


def main() -> None:
    out("=== Plex playlist hotkeys - setup check ===")
    out()

    try:
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        out(f"Could not read config.json: {exc}")
        finish()
        return

    plex_url = str(config.get("plex_url", "")).strip()
    plex_token = str(config.get("plex_token", "")).strip()
    out(f"plex_url from config.json: {plex_url}")
    if "PASTE_" in plex_token or not plex_token:
        out("plex_token is still the placeholder - paste your real token into config.json first.")
        finish()
        return
    out("plex_token: present (not shown)")
    out()

    try:
        from plexapi.server import PlexServer
    except ImportError:
        out("plexapi is not installed. Run once:  py -m pip install plexapi")
        finish()
        return

    try:
        plex = PlexServer(plex_url, plex_token)
    except Exception as exc:  # noqa: BLE001
        out(f"FAILED to connect to the Plex server: {exc}")
        out("Check plex_url (server IP/hostname + :32400) and that the server is running.")
        finish()
        return

    out(f"Server OK: {plex.friendlyName}  (version {plex.version})")
    out()
    out("--- Clients the server can see right now ---")
    out("Plexamp must be RUNNING when you run this, or it won't appear.")
    try:
        clients = plex.clients()
        if not clients:
            out("(none - open Plexamp on the target PC/device and run this again)")
        for c in clients:
            out(f"  client_name to copy: {c.title!r}   product={c.product}  device={c.device}")
            out(
                f"      advertised address={getattr(c, 'address', '?')}:{getattr(c, 'port', '?')}"
                f"   baseurl={getattr(c, '_baseurl', '?')}"
            )
            out(
                f"      machineIdentifier={getattr(c, 'machineIdentifier', '?')}"
                f"   protocolCapabilities={getattr(c, 'protocolCapabilities', '?')}"
            )
    except Exception as exc:  # noqa: BLE001
        out(f"(could not list clients: {exc})")

    out()
    out("--- Playlists on this server ---")
    try:
        playlists = plex.playlists()
        if not playlists:
            out("(none found)")
        for p in sorted(playlists, key=lambda x: x.title.lower()):
            # leafCount comes from the playlist listing itself - do NOT call
            # p.items() here, that downloads every track in the playlist
            # (35k+ for "Not Rated") and makes this check take minutes.
            count = getattr(p, "leafCount", None)
            if count is None:
                count = "?"
            out(f"  {p.title!r}   ratingKey={p.ratingKey}  items={count}")
    except Exception as exc:  # noqa: BLE001
        out(f"(could not list playlists: {exc})")

    out()
    out("Next: copy the exact Plexamp client name above into config.json,")
    out('then test with:  python play_playlist.py "5 Stars"')
    finish()


def finish() -> None:
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print()
    print(f"(Output also saved to {OUT_PATH.name})")
    try:
        input("Press Enter to close...")
    except EOFError:
        pass


if __name__ == "__main__":
    main()
