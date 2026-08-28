#!/usr/bin/env python3
"""Enable Sign in with Apple on the App ID and refresh the App Store profile.

Codemagic's cached IOS_APP_STORE profile predates the capability, so the signed
IPA only gets application-identifier / team-identifier. Native Apple sign-in
then fails on device with ASAuthorizationError.unknown (1000).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.adplay.app")
PROFILE_DIRS = [
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
]


def run(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(args), flush=True)
    return subprocess.run(args, check=check, text=True, capture_output=True)


def echo_proc(proc: subprocess.CompletedProcess[str]) -> None:
    if proc.stdout:
        print(proc.stdout, end="" if proc.stdout.endswith("\n") else "\n", flush=True)
    if proc.stderr:
        print(proc.stderr, end="" if proc.stderr.endswith("\n") else "\n", file=sys.stderr, flush=True)


def asc_json(args: list[str]) -> object:
    proc = run(["app-store-connect", *args, "--json"], check=False)
    echo_proc(proc)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode or 1)
    text = (proc.stdout or "").strip()
    if not text:
        return []
    return json.loads(text)


def resources(payload: object) -> list[dict]:
    if payload is None:
        return []
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        data = payload.get("data", payload)
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict)]
        if isinstance(data, dict):
            return [data]
    return []


def item_id(item: dict) -> str:
    return str(item.get("id") or item.get("Id") or "")


def nested(item: dict, *keys: str) -> object:
    current: object = item
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def decode_profile(path: Path) -> str:
    proc = subprocess.run(
        ["security", "cms", "-D", "-i", str(path)],
        check=False,
        text=True,
        capture_output=True,
    )
    return proc.stdout or ""


def local_bundle_profiles() -> list[tuple[Path, str]]:
    found: list[tuple[Path, str]] = []
    for directory in PROFILE_DIRS:
        if not directory.is_dir():
            continue
        for path in list(directory.glob("*.mobileprovision")) + list(directory.glob("*.provisionprofile")):
            decoded = decode_profile(path)
            if BUNDLE_ID in decoded:
                found.append((path, decoded))
    return found


def local_has_applesignin() -> bool:
    ok = False
    for path, decoded in local_bundle_profiles():
        if "applesignin" in decoded:
            print(f"OK: {path.name} includes applesignin", flush=True)
            ok = True
        else:
            print(f"MISSING applesignin: {path.name}", flush=True)
    return ok


def find_bundle_resource_id() -> str:
    payload = asc_json(
        [
            "bundle-ids",
            "list",
            "--bundle-id-identifier",
            BUNDLE_ID,
            "--strict-match-identifier",
        ]
    )
    for item in resources(payload):
        identifier = nested(item, "attributes", "identifier") or item.get("identifier")
        if identifier == BUNDLE_ID and item_id(item):
            return item_id(item)
    raise SystemExit(f"App ID {BUNDLE_ID} was not found in App Store Connect.")


def capability_enabled(bundle_resource_id: str) -> bool:
    payload = asc_json(["bundle-ids", "capabilities", bundle_resource_id])
    for item in resources(payload):
        cap = str(
            nested(item, "attributes", "capabilityType")
            or item.get("capabilityType")
            or item.get("capability_type")
            or ""
        ).upper()
        blob = json.dumps(item).upper()
        if cap in {"APPLE_ID_AUTH", "SIGN_IN_WITH_APPLE"} or "APPLE_ID_AUTH" in blob or "SIGN IN WITH APPLE" in blob:
            return True
    return False


def enable_apple_signin(bundle_resource_id: str) -> None:
    if capability_enabled(bundle_resource_id):
        print(f"App ID {BUNDLE_ID} already has Sign in with Apple.", flush=True)
        return
    print(f"Enabling Sign in with Apple on App ID {BUNDLE_ID} ({bundle_resource_id}).", flush=True)
    proc = run(
        [
            "app-store-connect",
            "bundle-ids",
            "enable-capabilities",
            bundle_resource_id,
            "--capability",
            "Sign In with Apple",
        ],
        check=False,
    )
    echo_proc(proc)
    if proc.returncode != 0:
        print(
            "Could not enable Sign in with Apple via the App Store Connect API. "
            "The Codemagic API key needs permission to edit identifiers, or enable "
            "the capability by hand at "
            "https://developer.apple.com/account/resources/identifiers/list",
            file=sys.stderr,
            flush=True,
        )
        raise SystemExit(proc.returncode or 1)
    if not capability_enabled(bundle_resource_id):
        raise SystemExit(f"Sign in with Apple is still missing on App ID {BUNDLE_ID}.")


def delete_stale_app_store_profiles(bundle_resource_id: str) -> None:
    payload = asc_json(
        [
            "bundle-ids",
            "profiles",
            "--bundle-ids",
            bundle_resource_id,
            "--type",
            "IOS_APP_STORE",
        ]
    )
    ids = [item_id(item) for item in resources(payload) if item_id(item)]
    if not ids:
        print("No remote IOS_APP_STORE profiles to replace.", flush=True)
        return
    for profile_id in ids:
        print(f"Deleting stale App Store profile {profile_id}.", flush=True)
        proc = run(
            ["app-store-connect", "profiles", "delete", profile_id, "--ignore-not-found"],
            check=False,
        )
        echo_proc(proc)
        if proc.returncode != 0:
            raise SystemExit(proc.returncode or 1)
    for path, decoded in local_bundle_profiles():
        if "applesignin" not in decoded:
            print(f"Removing local stale profile {path}.", flush=True)
            path.unlink(missing_ok=True)


def fetch_app_store_profile() -> None:
    proc = run(
        [
            "app-store-connect",
            "fetch-signing-files",
            BUNDLE_ID,
            "--type",
            "IOS_APP_STORE",
            "--platform",
            "IOS",
            "--create",
            "--strict-match-identifier",
        ],
        check=False,
    )
    echo_proc(proc)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode or 1)


def main() -> int:
    bundle_resource_id = find_bundle_resource_id()
    print(f"Bundle ID resource {bundle_resource_id} for {BUNDLE_ID}.", flush=True)
    enable_apple_signin(bundle_resource_id)
    if local_has_applesignin():
        return 0
    print("Refreshing the App Store profile so it picks up Sign in with Apple.", flush=True)
    delete_stale_app_store_profiles(bundle_resource_id)
    fetch_app_store_profile()
    if local_has_applesignin():
        return 0
    print(
        f"The App Store profile for {BUNDLE_ID} still lacks com.apple.developer.applesignin "
        "after refresh. Confirm Sign in with Apple on the App ID, then rerun.",
        file=sys.stderr,
        flush=True,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
