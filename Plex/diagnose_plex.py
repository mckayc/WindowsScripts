"""
Diagnostic for "the server thinks my Plexamp client is at the wrong address".

Run:
    python diagnose_plex.py
    (or double-click diagnose.bat)

It writes diagnose_output.txt in this folder. The Plex token is REDACTED
from everything it prints/writes, so the output file is safe to share.

What it checks:
  A. What the server's /clients endpoint actually says about each client
     (name, host, port, machineIdentifier) - this is where plexapi builds
     the client's address from, so if this is wrong, direct play fails.
  B. What plex.tv's resources API says - every device on the account and
     EVERY connection (IP, port, local/remote) it advertises.
  C. For each Plexamp connection found in B, it tries GET /resources on
     that exact address - a 200 means "this is the player's real companion
     address, put it in config.json as client_url".
  D. Current playback sessions, if anything is playing.
"""

import json
import re
from pathlib import Path
from xml.etree import ElementTree

import requests

HERE = Path(__file__).resolve().parent
CONFIG_PATH = HERE / "config.json"
OUT_PATH = HERE / "diagnose_output.txt"

lines: list[str] = []
TOKEN = ""


def redact(text: str) -> str:
    if TOKEN:
        text = text.replace(TOKEN, "<redacted>")
    text = re.sub(r"(X-Plex-Token=)[^&\"'\s<]+", r"\1<redacted>", text)
    text = re.sub(r"(token=)[0-9a-f-]{20,}", r"\1<redacted>", text, flags=re.I)
    return text


def out(text: str = "") -> None:
    text = redact(str(text))
    print(text)
    lines.append(text)


def get(url: str, **kwargs):
    headers = {"X-Plex-Token": TOKEN, "Accept": "application/xml", **kwargs.pop("headers", {})}
    return requests.get(url, headers=headers, timeout=15, **kwargs)


def main() -> None:
    global TOKEN
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    plex_url = str(config.get("plex_url", "")).rstrip("/")
    TOKEN = str(config.get("plex_token", "")).strip()
    wanted = str(config.get("client_name", "")).strip()

    out("=== Plex client-address diagnostic ===")
    out(f"Server: {plex_url}")
    out(f"Looking for client named: {wanted!r}")
    out()

    # --- A. server /clients -------------------------------------------------
    out("--- A. Server /clients (raw attributes) ---")
    try:
        r = get(f"{plex_url}/clients")
        out(f"HTTP {r.status_code}")
        root = ElementTree.fromstring(r.content)
        for elem in root:
            attrs = {k: v for k, v in elem.attrib.items() if k.lower() != "token"}
            out(f"  {attrs}")
    except Exception as exc:  # noqa: BLE001
        out(f"  FAILED: {exc}")
    out()

    # --- B. plex.tv resources ------------------------------------------------
    out("--- B. plex.tv /api/resources (devices + connections) ---")
    connections_to_probe: list[str] = []
    try:
        r = get("https://plex.tv/api/resources?includeHttps=1&includeIPv6=1")
        out(f"HTTP {r.status_code}")
        root = ElementTree.fromstring(r.content)
        for device in root:
            name = device.attrib.get("name", "?")
            product = device.attrib.get("product", "?")
            provides = device.attrib.get("provides", "")
            client_id = device.attrib.get("clientIdentifier", "?")
            interesting = "player" in provides or "plexamp" in product.lower() or wanted.lower() in name.lower()
            out(f"  Device: {name!r} product={product} provides={provides} clientIdentifier={client_id}"
                + ("" if interesting else "   (not a player, connections skipped)"))
            if not interesting:
                continue
            for conn in device:
                uri = conn.attrib.get("uri", "")
                out(f"      connection: address={conn.attrib.get('address')} port={conn.attrib.get('port')} "
                    f"local={conn.attrib.get('local')} protocol={conn.attrib.get('protocol')} uri={uri}")
                if uri.startswith("http://192.") or uri.startswith("http://10.") or uri.startswith("http://172."):
                    connections_to_probe.append(uri)
    except Exception as exc:  # noqa: BLE001
        out(f"  FAILED: {exc}")
    out()

    # --- C. probe each candidate companion address ---------------------------
    out("--- C. Probing each local player connection: GET <uri>/resources ---")
    if not connections_to_probe:
        out("  (no local player connections found in section B)")
    for uri in connections_to_probe:
        try:
            r = get(f"{uri}/resources")
            first = r.text.strip().splitlines()[0][:160] if r.text.strip() else "(empty body)"
            out(f"  {uri}/resources -> HTTP {r.status_code}  {first}")
            if r.status_code == 200:
                out(f"  *** THIS ONE ANSWERS. Put this in config.json:  \"client_url\": \"{uri}\"  ***")
        except Exception as exc:  # noqa: BLE001
            out(f"  {uri}/resources -> FAILED: {exc}")
    out()

    # --- D. sessions ----------------------------------------------------------
    out("--- D. Server /status/sessions (what is playing, if anything) ---")
    try:
        r = get(f"{plex_url}/status/sessions")
        root = ElementTree.fromstring(r.content)
        if len(root) == 0:
            out("  (nothing playing right now)")
        for track in root:
            player = track.find("Player")
            p_attrs = dict(player.attrib) if player is not None else {}
            out(f"  track={track.attrib.get('title')!r} player={p_attrs}")
    except Exception as exc:  # noqa: BLE001
        out(f"  FAILED: {exc}")
    out()
    out("Share diagnose_output.txt from this folder if you need help with the result - token is redacted.")
    finish()


def finish() -> None:
    OUT_PATH.write_text(redact("\n".join(lines)) + "\n", encoding="utf-8")
    print()
    print(f"(Output also saved to {OUT_PATH.name})")
    try:
        input("Press Enter to close...")
    except EOFError:
        pass


if __name__ == "__main__":
    main()
