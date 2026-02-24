#!/usr/bin/env python3
"""Insert a new <item> into dist/appcast.xml before the insertion marker."""
import sys

# VERSION is the human-readable string (e.g. "1.0.0"); build number is derived
# by stripping dots so Sparkle's integer comparison works correctly.
version       = sys.argv[1]   # e.g. "1.0.0"
sig           = sys.argv[2]
length        = sys.argv[3]
date          = sys.argv[4]
url           = sys.argv[5]
notes         = sys.argv[6] if len(sys.argv) > 6 else ""

# sparkle:version must be an integer for correct update comparison
build_number = version.replace(".", "")  # "1.0.0" -> "100"

# Guard against ]]> breaking CDATA
safe_notes = notes.replace("]]>", "]]]]><![CDATA[>")
notes_html = f"<ul><li>{safe_notes}</li></ul>" if safe_notes else "<ul><li>Bug fixes and improvements.</li></ul>"

item = f"""    <item>
        <title>Version {version}</title>
        <pubDate>{date}</pubDate>
        <sparkle:version>{build_number}</sparkle:version>
        <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        <description><![CDATA[{notes_html}]]></description>
        <enclosure url="{url}" length="{length}" type="application/zip" sparkle:edSignature="{sig}" />
    </item>
"""

MARKER = "    <!-- Items added here by `make publish-update` -->"

with open("dist/appcast.xml") as f:
    content = f.read()

if MARKER not in content:
    print("Error: insertion marker not found in dist/appcast.xml", file=sys.stderr)
    sys.exit(1)

content = content.replace(MARKER, item + MARKER)

with open("dist/appcast.xml", "w") as f:
    f.write(content)

print(f"  ✓ Appended entry for version {version} (build {build_number})")
