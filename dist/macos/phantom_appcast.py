"""
Writes the Sparkle appcast for a Phantom release.

Phantom's feeds live where Phantom's releases live: every feed is an asset of
every GitHub release, and the app reads its own through the stable alias
    https://github.com/ipetinate/phantom/releases/latest/download/<feed>
so no server, bucket or domain is involved — only this repository.

One release ships two DMGs — a universal one and an Apple-Silicon-only one
thinned from it — and each gets its own feed, so an app never updates itself
into the other flavour. The app picks the feed by counting the architectures in
its own executable (UpdateDelegate.swift).

Expects, in the current directory:
    - the signature file  the output of Sparkle's sign_update for the DMG
    - the feed file       the previous release's feed, when there is one; a
                          missing or empty file starts a new feed. The history
                          is kept so a reader several versions behind still
                          sees an entry, and pruned so the file cannot grow
                          forever.

And in the environment:
    - PHANTOM_VERSION   X.Y.Z, what CFBundleShortVersionString says
    - PHANTOM_BUILD     the build number, what CFBundleVersion says — Sparkle
                        compares this one, so it must be monotonic
    - PHANTOM_TAG       the git tag the DMG is published under
    - PHANTOM_COMMIT    the short commit hash
    - PHANTOM_DMG       the DMG asset this feed points at, default Phantom.dmg
    - PHANTOM_APPCAST   the feed file, default appcast.xml
    - PHANTOM_SIGNATURE the signature file, default sign_update.txt
    - PHANTOM_FLAVOR    what to call this build in the feed's own title and in
                        the item description, default Universal

Writes the feed file in place.

The build number is the item's identity. An item with the same build is replaced
rather than duplicated: two items claiming one build would make Sparkle report a
bad signature whenever it picked the wrong one.
"""

import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

REPO = "https://github.com/ipetinate/phantom"
MINIMUM_SYSTEM_VERSION = "13.0"
KEEP = 15
PUBDATE = "%a, %d %b %Y %H:%M:%S %z"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"

version = os.environ["PHANTOM_VERSION"]
build = os.environ["PHANTOM_BUILD"]
tag = os.environ["PHANTOM_TAG"]
commit = os.environ["PHANTOM_COMMIT"]
dmg = os.environ.get("PHANTOM_DMG", "Phantom.dmg")
appcast = os.environ.get("PHANTOM_APPCAST", "appcast.xml")
signature = os.environ.get("PHANTOM_SIGNATURE", "sign_update.txt")
flavor = os.environ.get("PHANTOM_FLAVOR", "Universal")

with open(signature, encoding="utf-8") as f:
    attrs = {}
    for pair in f.read().split(" "):
        key, value = pair.split("=", 1)
        value = value.strip()
        if value.startswith('"'):
            value = value[1:-1]
        attrs[key] = value

for required in ("sparkle:edSignature", "length"):
    if not attrs.get(required):
        sys.exit(f"{signature} has no {required}: {dmg} was not signed")

ET.register_namespace("sparkle", SPARKLE)

if os.path.exists(appcast) and os.path.getsize(appcast) > 0:
    tree = ET.parse(appcast)
    channel = tree.find("channel")
else:
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = f"Phantom ({flavor})"
    ET.SubElement(channel, "link").text = f"{REPO}/releases"
    ET.SubElement(channel, "description").text = f"Phantom releases ({flavor})"
    ET.SubElement(channel, "language").text = "en"
    tree = ET.ElementTree(root)

namespaces = {"sparkle": SPARKLE}
for item in list(channel.findall("item")):
    sparkle_version = item.find("sparkle:version", namespaces)
    if sparkle_version is not None and sparkle_version.text == build:
        channel.remove(item)
    elif item.find("pubDate") is None:
        channel.remove(item)

items = channel.findall("item")
items.sort(key=lambda i: datetime.strptime(i.find("pubDate").text, PUBDATE))
for item in items[: max(0, len(items) - (KEEP - 1))]:
    channel.remove(item)

item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = f"Phantom {version}"
ET.SubElement(item, "pubDate").text = datetime.now(timezone.utc).strftime(PUBDATE)
ET.SubElement(item, f"{{{SPARKLE}}}version").text = build
ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = MINIMUM_SYSTEM_VERSION
ET.SubElement(item, "link").text = f"{REPO}/releases/tag/{tag}"
ET.SubElement(item, f"{{{SPARKLE}}}releaseNotesLink").text = f"{REPO}/releases/tag/{tag}"
ET.SubElement(item, "description").text = (
    f"Phantom {version} ({flavor}), build {build}, commit {commit}."
)
ET.SubElement(
    item,
    "enclosure",
    {
        "url": f"{REPO}/releases/download/{tag}/{dmg}",
        "type": "application/octet-stream",
        "length": attrs["length"],
        f"{{{SPARKLE}}}edSignature": attrs["sparkle:edSignature"],
    },
)

ET.indent(tree, space="  ")
tree.write(appcast, encoding="utf-8", xml_declaration=True)
print(f"{appcast}: {len(channel.findall('item'))} item(s), newest {version} (build {build})")
