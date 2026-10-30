#!/usr/bin/env python3
"""Write the Sparkle appcast for one release. Called by Scripts/make-appcast.sh, which signs the zip.

The feed only ever lists the release it ships with: it is published as that release's
`appcast.xml` asset and read through /releases/latest/download/, so the newest release's feed is the
one every installed Cellar sees. Sparkle needs nothing older than that to offer an update.

The release notes arrive as Markdown (built from the issues the release closed) and are shown in
Sparkle's update window, which renders HTML. This converts the small subset those notes use —
headings, bullets, paragraphs, links, `code`, **bold**, #123 issue references — and escapes
everything else, so a stray `<` in an issue title is text, not markup.

Stdlib only, Python 3.9 floor (skills/python.md).
"""
import argparse
import base64
import hashlib
import html
import os
import re
import sys
from datetime import datetime, timezone

REPO = "https://github.com/Echarnus/Cellar"
FEED = REPO + "/releases/latest/download/appcast.xml"

INLINE = re.compile(
    r"`(?P<code>[^`]+)`"
    r"|\*\*(?P<bold>[^*]+)\*\*"
    r"|\[(?P<text>[^\]]+)\]\((?P<url>https?://[^)\s]+)\)"
    r"|(?P<bare>https?://[^\s<>()]+)"
    r"|(?<![\w/&])#(?P<issue>\d+)\b"
)


def inline(text):
    """Escape a line of Markdown, turning its few inline forms into HTML."""
    out = []
    pos = 0
    for m in INLINE.finditer(text):
        out.append(html.escape(text[pos:m.start()]))
        if m.group("code") is not None:
            out.append("<code>" + html.escape(m.group("code")) + "</code>")
        elif m.group("bold") is not None:
            out.append("<strong>" + html.escape(m.group("bold")) + "</strong>")
        elif m.group("url") is not None:
            out.append('<a href="' + html.escape(m.group("url")) + '">' + html.escape(m.group("text")) + "</a>")
        elif m.group("bare") is not None:
            url = html.escape(m.group("bare"))
            out.append('<a href="' + url + '">' + url + "</a>")
        else:
            n = m.group("issue")
            out.append('<a href="' + REPO + "/issues/" + n + '">#' + n + "</a>")
        pos = m.end()
    out.append(html.escape(text[pos:]))
    return "".join(out)


def markdown_to_html(md):
    blocks = []
    para = []
    items = []

    def flush():
        if para:
            blocks.append("<p>" + " ".join(inline(line) for line in para) + "</p>")
            del para[:]
        if items:
            blocks.append("<ul>" + "".join("<li>" + inline(i) + "</li>" for i in items) + "</ul>")
            del items[:]

    for raw in md.splitlines():
        line = raw.strip()
        if not line or line.startswith("<!--"):
            flush()
            continue
        heading = re.match(r"(#{1,6})\s+(.*)", line)
        bullet = re.match(r"[-*+]\s+(.*)", line)
        if heading:
            flush()
            # The update window is small; nothing in it should shout louder than an h3.
            level = min(len(heading.group(1)) + 1, 4)
            blocks.append("<h%d>%s</h%d>" % (level, inline(heading.group(2)), level))
        elif bullet:
            if para:
                flush()
            items.append(bullet.group(1))
        else:
            if items:
                flush()
            para.append(line)
    flush()
    return "\n".join(blocks)


# Ed25519, only far enough to turn a private key into its public key (RFC 8032 §5.1.5). The
# release's signing secret and the key in Resources/sparkle-public-key are kept in two places; if
# they ever disagree, every installed Cellar rejects the update as tampered with. Better that the
# release job fails here than that players see that.
P = 2 ** 255 - 19
D = -121665 * pow(121666, P - 2, P) % P
GY = 4 * pow(5, P - 2, P) % P
GX_SQ = (GY * GY - 1) * pow(D * GY * GY + 1, P - 2, P) % P
GX = pow(GX_SQ, (P + 3) // 8, P)
if (GX * GX - GX_SQ) % P:
    GX = GX * pow(2, (P - 1) // 4, P) % P
if GX % 2:
    GX = P - GX


def _add(a, b):
    (x1, y1, z1, t1), (x2, y2, z2, t2) = a, b
    a_ = (y1 - x1) * (y2 - x2) % P
    b_ = (y1 + x1) * (y2 + x2) % P
    c = 2 * t1 * t2 * D % P
    d = 2 * z1 * z2 % P
    e, f, g, h = b_ - a_, d - c, d + c, b_ + a_
    return (e * f % P, g * h % P, f * g % P, e * h % P)


def public_key(secret_b64):
    """Sparkle's private key (base64: a 32-byte seed, or the older 96-byte form) -> public key, base64."""
    secret = base64.b64decode(secret_b64.strip())
    if len(secret) == 96:
        return base64.b64encode(secret[64:]).decode()
    if len(secret) != 32:
        sys.exit("SPARKLE_ED_PRIVATE_KEY is not a Sparkle EdDSA key (%d bytes decoded)" % len(secret))
    h = hashlib.sha512(secret).digest()
    scalar = int.from_bytes(h[:32], "little")
    scalar &= (1 << 254) - 8
    scalar |= 1 << 254
    result, point = (0, 1, 1, 0), (GX, GY, 1, GX * GY % P)
    while scalar:
        if scalar & 1:
            result = _add(result, point)
        point = _add(point, point)
        scalar >>= 1
    x, y, z, _ = result
    zi = pow(z, P - 2, P)
    x, y = x * zi % P, y * zi % P
    return base64.b64encode((y | (x & 1) << 255).to_bytes(32, "little")).decode()


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--version", required=True)
    p.add_argument("--notes", required=True, help="release notes, Markdown")
    p.add_argument("--signature", required=True, help="sparkle:edSignature value")
    p.add_argument("--public-key", required=True, help="the SUPublicEDKey the app ships with")
    p.add_argument("--length", required=True, type=int, help="size of the zip in bytes")
    p.add_argument("--min-system", default="13.0")
    p.add_argument("--out", required=True)
    a = p.parse_args()

    # The secret comes from the environment, never argv, where `ps` would show it.
    secret = os.environ.get("SPARKLE_ED_PRIVATE_KEY", "")
    if not secret.strip():
        sys.exit("SPARKLE_ED_PRIVATE_KEY is not set")
    if public_key(secret) != a.public_key.strip():
        sys.exit("SPARKLE_ED_PRIVATE_KEY does not match Resources/sparkle-public-key — installed copies "
                 "of Cellar would reject this update. Re-run Scripts/sparkle-keys.sh, or fix the secret.")

    with open(a.notes, encoding="utf-8") as f:
        notes = markdown_to_html(f.read())
    if "]]>" in notes:
        sys.exit("release notes contain ']]>', which would end the CDATA block early")

    tag = "v" + a.version
    q = html.escape  # quotes too, by default — every value below may land in an attribute
    enclosure = "%s/releases/download/%s/Cellar-App-%s.zip" % (REPO, tag, a.version)
    xml = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Cellar</title>
    <link>{feed}</link>
    <description>Updates to Cellar, the Windows-games-on-Mac layer.</description>
    <language>en</language>
    <item>
      <title>Cellar {version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minsys}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{notes_link}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
{notes}
]]></description>
      <enclosure url="{url}" length="{length}" type="application/octet-stream" sparkle:edSignature="{sig}"/>
    </item>
  </channel>
</rss>
""".format(
        feed=q(FEED),
        version=q(a.version),
        date=datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000"),
        minsys=q(a.min_system),
        notes_link=q("%s/releases/tag/%s" % (REPO, tag)),
        notes=notes,
        url=q(enclosure),
        length=a.length,
        sig=q(a.signature),
    )
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(xml)


if __name__ == "__main__":
    main()
