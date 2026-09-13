#!/usr/bin/env python3
"""スクリーンショットを App Store Connect へ登録する。

JSONのやり取りだけでは終わらない。**画像の実体は、返ってきた uploadOperations の
URLへ自分でPUTする。** 送り終えたら uploaded=true と md5 を PATCH して初めて確定する。
どれか1つ落とすと「アップロード済みだが壊れている」状態になり、画面から消せなくなる。

    ./Tools-UploadScreenshots.py <appStoreVersionLocalization id> <表示種別> <画像フォルダ>

例:
    ./Tools-UploadScreenshots.py 22e6... APP_IPHONE_65 store/screenshots-65
"""
from __future__ import annotations

import hashlib
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from importlib import import_module

asc = import_module("Tools-ASC")


def api(method: str, path: str, body=None):
    status, payload = asc.call(method, path, json.dumps(body, ensure_ascii=False) if body else None)
    if not 200 <= status < 300:
        print(f"HTTP {status} {method} {path}")
        print(json.dumps(payload, ensure_ascii=False, indent=2)[:1200])
        sys.exit(1)
    return payload


def put_bytes(op: dict, chunk: bytes):
    req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
    for h in op.get("requestHeaders") or []:
        req.add_header(h["name"], h["value"])
    try:
        with urllib.request.urlopen(req) as res:
            return res.status
    except urllib.error.HTTPError as e:
        print("アップロード失敗:", e.code, e.read()[:400].decode(errors="replace"))
        sys.exit(1)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    loc_id, display_type, folder = sys.argv[1], sys.argv[2], Path(sys.argv[3])

    # 同じ表示種別のセットが既にあれば使い回す。作り直すと前の画像が宙に浮く。
    sets = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    existing = [s for s in sets.get("data", [])
                if s["attributes"]["screenshotDisplayType"] == display_type]
    if existing:
        set_id = existing[0]["id"]
        print(f"既存のセットを使う: {set_id}")
        shots = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots")
        for s in shots.get("data", []):
            api("DELETE", f"/v1/appScreenshots/{s['id']}")
            print("  古い画像を消した:", s["attributes"].get("fileName"))
    else:
        created = api("POST", "/v1/appScreenshotSets", {
            "data": {"type": "appScreenshotSets",
                     "attributes": {"screenshotDisplayType": display_type},
                     "relationships": {"appStoreVersionLocalization": {
                         "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
        set_id = created["data"]["id"]
        print(f"セットを作った: {set_id}")

    for path in sorted(folder.glob("*.png")):
        data = path.read_bytes()
        made = api("POST", "/v1/appScreenshots", {
            "data": {"type": "appScreenshots",
                     "attributes": {"fileSize": len(data), "fileName": path.name},
                     "relationships": {"appScreenshotSet": {
                         "data": {"type": "appScreenshotSets", "id": set_id}}}}})
        shot_id = made["data"]["id"]
        for op in made["data"]["attributes"]["uploadOperations"]:
            put_bytes(op, data[op["offset"]: op["offset"] + op["length"]])
        api("PATCH", f"/v1/appScreenshots/{shot_id}", {
            "data": {"type": "appScreenshots", "id": shot_id,
                     "attributes": {"uploaded": True,
                                    "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(f"  入れた: {path.name}  {len(data) // 1024}KB")

    print("完了")


if __name__ == "__main__":
    main()
