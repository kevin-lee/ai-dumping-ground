# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Download a music track from its Free Music Archive (FMA) or OpenGameArt (OGA) page, check its license,
and keep proof of the license for later Content ID disputes.

  uv run --script fetch_music.py <track page URL> sources/music [--name windows-down] [--no-wayback]

Writes to the folder:
  <name>.mp3                 the exact file used (its SHA-256 goes into MUSIC.md)
  <name>-license-page.html   a copy of the track page as it showed the license on the download date
  MUSIC.md                   title, artist, album, license, URLs, SHA-256, date, Wayback snapshot, credit line

CC0 / public domain is accepted. CC BY is accepted with a warning, because the video description must then
credit the artist. NonCommercial (NC) and NoDerivatives (ND) licenses are refused: NC rules out a product or
monetised video, and ND forbids putting the music under a video at all.
"""

import argparse
import datetime
import hashlib
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

UA = {"User-Agent": "Mozilla/5.0"}  # FMA answers 403 to Python's default user agent


def get(url: str, timeout: int = 60) -> tuple[bytes, str, str]:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(), r.headers.get("Content-Type", ""), r.geturl()


def fma(page: str, url: str) -> dict:
    infos = [json.loads(html.unescape(m)) for m in re.findall(r"data-track-info='([^']+)'", page)]
    if not infos:
        sys.exit("no track information found on this FMA page; is it a track page?")
    want = url.split("?")[0].rstrip("/") + "/"
    info = next((i for i in infos if i.get("url", "").rstrip("/") + "/" == want), infos[0])
    lic = re.search(r'rel="license"[^>]*href="([^"]+)"[^>]*>\s*([^<]*?)\s*</a>', page) or \
        re.search(r'href="(https?://creativecommons\.org/[^"]+)"[^>]*>\s*([^<]*?)\s*</a>', page)
    return {
        "title": info.get("title", ""), "artist": info.get("artistName", ""), "album": info.get("albumTitle", ""),
        "file": info["fileUrl"], "license_url": lic.group(1) if lic else "", "license": (lic.group(2) if lic else "").strip(),
    }


def oga(page: str, url: str) -> dict:
    title = re.search(r"<title>\s*([^<|]+?)\s*\|", page)
    files = re.findall(r'href="(https?://opengameart\.org/sites/default/files/[^"]+\.(?:mp3|ogg|wav))"', page)
    if not files:
        sys.exit("no audio file link found on this OpenGameArt page")
    block = page[page.find("License(s)"):][:1500] if "License(s)" in page else page
    lic = re.search(r"""href=['"](https?://creativecommons\.org/[^'"]+)['"]""", block)
    names = re.findall(r"class='license-name'>([^<]+)<", block)
    author = re.search(r'field-name-author-submitter.*?<a[^>]*>([^<]+)</a>', page, re.S)
    mp3 = next((f for f in files if f.endswith(".mp3")), files[0])
    return {"title": title.group(1) if title else Path(mp3).stem, "artist": author.group(1).strip() if author else "",
            "album": "", "file": mp3, "license_url": lic.group(1) if lic else "", "license": ", ".join(n.strip() for n in names)}


def classify(lic_url: str, lic_text: str) -> str:
    s = f"{lic_url} {lic_text}".lower()
    if "publicdomain" in s or "cc0" in s or "public domain" in s:
        return "cc0"
    if re.search(r"by-nc|by-nd|noncommercial|non-commercial|noderiv|\bnc\b|\bnd\b", s):
        return "refuse"
    if "/by/" in s or "attribution" in s or re.search(r"\bcc by\b", s):
        return "by"
    return "unknown"


def wayback(url: str) -> str:
    try:
        _, _, final = get("https://web.archive.org/save/" + url, timeout=150)
        return final if "/web/" in final else ""
    except Exception as e:  # the archive is often slow; this is optional proof
        print(f"Wayback snapshot failed ({e}); try again later at https://web.archive.org/save/{url}")
        return ""


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("url")
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--name", help="file name without extension (default: from the title)")
    ap.add_argument("--no-wayback", action="store_true")
    a = ap.parse_args()

    raw, _, _ = get(a.url)
    page = raw.decode("utf-8", errors="replace")
    if "freemusicarchive.org" in a.url:
        t = fma(page, a.url)
    elif "opengameart.org" in a.url:
        t = oga(page, a.url)
    else:
        sys.exit("only freemusicarchive.org and opengameart.org pages are supported; for other sources download by hand and fill MUSIC.md")
    t["title"] = re.sub(r"\.mp3$", "", t["title"].strip(), flags=re.I)
    kind = classify(t["license_url"], t["license"])
    if kind == "refuse":
        sys.exit(f'license "{t["license"]}" ({t["license_url"]}) does not allow this use (NonCommercial or NoDerivatives); pick another track')
    if kind == "unknown":
        sys.exit(f'could not confirm the license on the page (found "{t["license"]}" {t["license_url"]}); check it by hand')

    name = a.name or re.sub(r"[^a-z0-9]+", "-", t["title"].lower()).strip("-")
    a.out_dir.mkdir(parents=True, exist_ok=True)
    data, ctype, _ = get(t["file"], timeout=300)
    if not (ctype.startswith("audio") or data[:3] == b"ID3" or data[:2] == b"\xff\xfb"):
        sys.exit(f"the file URL did not return audio ({ctype})")
    ext = Path(t["file"].split("?")[0]).suffix or ".mp3"
    audio = a.out_dir / f"{name}{ext}"
    audio.write_bytes(data)
    (a.out_dir / f"{name}-license-page.html").write_bytes(raw)
    sha = hashlib.sha256(data).hexdigest()
    snap = "" if a.no_wayback else wayback(a.url)
    today = datetime.date.today().isoformat()

    credit = f'"{t["title"]}" by {t["artist"]}' + (f' ({t["album"]})' if t["album"] else "") + f", {t['license']}"
    attribution = ("Not required (CC0). A credit in the video description is a kind gesture." if kind == "cc0"
                   else "REQUIRED (CC BY): put the credit line, the license name and its link in the video description.")
    md = f"""# Background music

- Track: {t["title"]}
- Artist: {t["artist"]}
- Album: {t["album"] or "-"}
- Track page: {a.url}
- File: {t["file"]}
- License: {t["license"]} ({t["license_url"]})
- Commercial use: allowed
- Attribution: {attribution}
- Downloaded: {today}
- File: `{audio.name}`, SHA-256 `{sha}`
- Page copy: `{name}-license-page.html`
- Wayback snapshot: {snap or "none yet (https://web.archive.org/save/" + a.url + ")"}

Credit line: {credit}

## How it is used

(Fill in after mixing: tempo, the drop, cuts, ending.)

## Before uploading

Keep this file, the page copy and the snapshot. CC0 and Creative Commons recordings cannot be registered with
YouTube's Content ID, but wrong claims still happen. If one appears, dispute it with this proof: the license
page, the snapshot and the file's SHA-256.
"""
    (a.out_dir / "MUSIC.md").write_text(md, encoding="utf-8")
    print(f"{audio} ({len(data) / 1e6:.1f} MB, sha256 {sha[:12]}...)")
    print(f"license: {t['license']} -> {'CC0, no attribution needed' if kind == 'cc0' else 'CC BY, attribution REQUIRED'}")
    print(f"{a.out_dir / 'MUSIC.md'} written; snapshot: {snap or 'none'}")


if __name__ == "__main__":
    main()
