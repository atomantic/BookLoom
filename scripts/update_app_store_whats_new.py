#!/usr/bin/env python3
"""Update App Store Connect "What's New" text for prepared platform versions."""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


API_ROOT = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_PLATFORMS = ("IOS", "MAC_OS")


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        raise SystemExit(f".env file not found at {path}")
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def sign_token(key_id: str, issuer_id: str, key_path: Path) -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = b64url(
        json.dumps(
            {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = header + b"." + claims
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=signing_input,
        capture_output=True,
        check=True,
    ).stdout

    if not der or der[0] != 0x30:
        raise RuntimeError("openssl returned an unexpected ECDSA signature")
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    r_len = der[index + 1]
    r = der[index + 2 : index + 2 + r_len]
    index += 2 + r_len
    s_len = der[index + 1]
    s = der[index + 2 : index + 2 + s_len]
    r = r.lstrip(b"\x00").rjust(32, b"\x00")
    s = s.lstrip(b"\x00").rjust(32, b"\x00")
    return (signing_input + b"." + b64url(r + s)).decode()


class AppStoreConnect:
    def __init__(self, token: str) -> None:
        self.token = token

    def request(self, method: str, path: str, payload: dict | None = None) -> dict:
        body = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(
            f"{API_ROOT}{path}",
            data=body,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise RuntimeError(f"{method} {path} failed with HTTP {error.code}: {detail}") from error
        return json.loads(raw) if raw else {}

    def get(self, path: str, params: dict[str, str] | None = None) -> dict:
        query = "" if not params else "?" + urllib.parse.urlencode(params)
        return self.request("GET", path + query)

    def patch(self, path: str, payload: dict) -> dict:
        return self.request("PATCH", path, payload)


def first(data: dict, label: str) -> dict:
    items = data.get("data", [])
    if not items:
        raise RuntimeError(f"No {label} found")
    return items[0]


def update_platform(client: AppStoreConnect, app_id: str, version: str, platform: str, locale: str, notes: str) -> str:
    app_version = first(
        client.get(
            f"/apps/{app_id}/appStoreVersions",
            {
                "filter[platform]": platform,
                "filter[versionString]": version,
                "limit": "1",
            },
        ),
        f"{platform} App Store version {version}",
    )
    app_version_id = app_version["id"]
    localizations = client.get(
        f"/appStoreVersions/{app_version_id}/appStoreVersionLocalizations",
        {"filter[locale]": locale, "limit": "1"},
    )
    localization = first(localizations, f"{platform} {locale} localization for version {version}")
    localization_id = localization["id"]
    client.patch(
        f"/appStoreVersionLocalizations/{localization_id}",
        {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": localization_id,
                "attributes": {"whatsNew": notes},
            }
        },
    )
    return app_version_id


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--bundle-id", default="net.shadowpuppet.PlotLoom")
    parser.add_argument("--locale", default="en-US")
    parser.add_argument("--notes", required=True)
    parser.add_argument("--env-file", default=".env")
    parser.add_argument("--platform", action="append", choices=DEFAULT_PLATFORMS)
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    key_path = Path(os.path.expandvars(env["APPSTORE_API_PRIVATE_KEY_PATH"])).expanduser()
    token = sign_token(env["APPSTORE_API_KEY_ID"], env["APPSTORE_ISSUER_ID"], key_path)
    client = AppStoreConnect(token)

    app = first(client.get("/apps", {"filter[bundleId]": args.bundle_id, "limit": "1"}), f"app {args.bundle_id}")
    platforms = args.platform or list(DEFAULT_PLATFORMS)
    for platform in platforms:
        app_version_id = update_platform(client, app["id"], args.version, platform, args.locale, args.notes)
        print(f"Updated {platform} {args.version} ({args.locale}) whatsNew on App Store version {app_version_id}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
