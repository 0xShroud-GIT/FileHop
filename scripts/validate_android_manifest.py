#!/usr/bin/env python3
"""Deterministic Android manifest structural validation for FileHop.

Parses AndroidManifest.xml as real XML (stdlib xml.etree, no dependency) and
proves the <application> element exists with android:label / android:name /
android:icon as XML ATTRIBUTES, not text-node content. Filename grep is
never the sole proof.

Exit 0 on PASS; non-zero with a diagnostic on FAIL.
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

EXPECTED_ATTRIBUTES = {
    "label": "FileHop",
    "name": "${applicationName}",
    "icon": "@mipmap/ic_launcher",
}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    root_dir = Path(__file__).resolve().parent.parent
    manifest_path = root_dir / "android/app/src/main/AndroidManifest.xml"
    if len(sys.argv) > 1:
        manifest_path = Path(sys.argv[1])
    if not manifest_path.is_file():
        fail(f"manifest not found: {manifest_path}")

    try:
        tree = ET.parse(manifest_path)
    except ET.ParseError as error:
        fail(f"manifest is not well-formed XML: {error}")

    manifest = tree.getroot()
    if manifest.tag != "manifest":
        fail(f"root element is {manifest.tag!r}, expected 'manifest'")

    application = manifest.find("application")
    if application is None:
        fail("<application> element is missing")

    for local_name, expected in EXPECTED_ATTRIBUTES.items():
        actual = application.get(ANDROID_NS + local_name)
        if actual is None:
            fail(
                f"<application> lacks android:{local_name} as an XML "
                f"attribute (it must not be text content)"
            )
        if actual != expected:
            fail(
                f"android:{local_name} is {actual!r}, expected {expected!r}"
            )

    # Attributes must not ALSO appear as stray text nodes inside the element.
    text_fragments = [application.text or ""] + [
        (child.tail or "") for child in application
    ]
    for fragment in text_fragments:
        stripped = fragment.strip()
        if stripped:
            fail(
                "<application> contains unexpected text content: "
                f"{stripped[:80]!r}"
            )

    child_tags = [child.tag for child in application]
    if "activity" not in child_tags:
        fail("<application> lost its <activity> child")
    if "meta-data" not in child_tags:
        fail("<application> lost its <meta-data> child")

    activity = application.find("activity")
    if activity.get(ANDROID_NS + "name") != ".MainActivity":
        fail("launcher activity android:name is not .MainActivity")

    print("PASS: AndroidManifest.xml is well-formed XML;")
    print("  <application> android:label/name/icon are real attributes;")
    print(f"  children preserved: {child_tags}")


if __name__ == "__main__":
    main()
