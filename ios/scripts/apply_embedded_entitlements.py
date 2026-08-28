#!/usr/bin/env python3
"""Sign the TestFlight app with the entitlements already in its provisioning profile.

The AdPlay App Store profile includes Sign in with Apple. Xcode's export has been
writing a default entitlements plist (app id / team only) and dropping it.
"""

from __future__ import annotations

import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path


def run(args: list[str]) -> None:
    print("+", " ".join(args), flush=True)
    proc = subprocess.run(args, check=False, text=True, capture_output=True)
    if proc.stdout:
        print(proc.stdout, end="" if proc.stdout.endswith("\n") else "\n", flush=True)
    if proc.returncode != 0:
        if proc.stderr:
            print(proc.stderr, end="" if proc.stderr.endswith("\n") else "\n", file=sys.stderr, flush=True)
        raise SystemExit(proc.returncode)


def profile_entitlements(app: Path) -> dict:
    embedded = app / "embedded.mobileprovision"
    if not embedded.is_file():
        raise SystemExit(f"No embedded.mobileprovision in {app}")
    raw = subprocess.check_output(["security", "cms", "-D", "-i", str(embedded)])
    data = plistlib.loads(raw)
    ents = data.get("Entitlements")
    if not isinstance(ents, dict):
        raise SystemExit("embedded.mobileprovision has no Entitlements")
    print(f"Profile {data.get('Name')} entitlements: {sorted(ents)}", flush=True)
    return ents


def distribution_identity() -> str:
    out = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    for line in out.splitlines():
        if "Apple Distribution" in line and '"' in line:
            return line.split('"')[1]
    raise SystemExit(f"No Apple Distribution identity in keychain:\n{out}")


def main() -> int:
    root = Path(os.environ.get("CM_BUILD_DIR", Path.cwd()))
    ipas = sorted((root / "build/ios/ipa").glob("*.ipa"))
    if not ipas:
        raise SystemExit("No IPA in build/ios/ipa")
    ipa = ipas[0]
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp)
        run(["unzip", "-qo", str(ipa), "-d", str(dest)])
        apps = list(dest.glob("Payload/*.app"))
        if not apps:
            raise SystemExit("IPA has no Payload/*.app")
        app = apps[0]
        ents = profile_entitlements(app)
        if "com.apple.developer.applesignin" not in ents:
            raise SystemExit("embedded profile does not include Sign in with Apple")
        ent_file = dest / "profile.entitlements"
        ent_file.write_bytes(plistlib.dumps(ents))
        run(
            [
                "codesign",
                "--force",
                "--sign",
                distribution_identity(),
                "--entitlements",
                str(ent_file),
                "--timestamp",
                "--generate-entitlement-der",
                str(app),
            ]
        )
        pack = dest / "pack"
        pack.mkdir()
        (dest / "Payload").rename(pack / "Payload")
        for extra in ("SwiftSupport", "Symbols"):
            src = dest / extra
            if src.exists():
                src.rename(pack / extra)
        ipa.unlink()
        cwd = Path.cwd()
        os.chdir(pack)
        try:
            run(["zip", "-qry", str(ipa), "."])
        finally:
            os.chdir(cwd)
    print(f"Re-signed {ipa.name} with the embedded profile entitlements.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
