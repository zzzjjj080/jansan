#!/usr/bin/env python3
"""実機ビルド用のプロビジョニングプロファイルを作り直して、手元へ置く。

**引き継ぎ書 4-28 は「APIでは作れない」と書いていたが、作れた。**
`POST /v1/profiles` が 201 を返す。必要なのは3つの関係だけ。

    バンドルID（機能を有効にしてあるもの） / 開発用の証明書 / 端末

Xcode にアカウントを追加していない状態でも、これで実機ビルドが通る。
自動署名だと "No Accounts" で止まり、ワイルドカードの
"iOS Team Provisioning Profile: *" に落ちて HealthKit が無いと言われる。

有効期限は1年。切れたら、このスクリプトをもう一度走らせる。
端末を足したときも走らせる（プロファイルは作った時点の端末しか入らない）。

    ./Tools-MakeProfile.py
"""
from __future__ import annotations

import base64
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ASC = HERE / "Tools-ASC.py"

PROFILE_NAME = "Jansan iOS Development"
BUNDLE_ID = "com.zzzjjj080.Jansan"


def asc(method: str, path: str, body: str | None = None):
    cmd = [sys.executable, str(ASC), method, path] + ([body] if body else [])
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    # 1行目は "HTTP 200" のような状態行
    head, _, rest = out.partition("\n")
    if not head.startswith("HTTP 2"):
        raise SystemExit(f"{path} で失敗しました:\n{out}")
    return json.loads(rest) if rest.strip() else {}


def main() -> None:
    bundle = next((x["id"] for x in asc("get", "/v1/bundleIds?limit=200")["data"]
                   if x["attributes"]["identifier"] == BUNDLE_ID), None)
    if not bundle:
        raise SystemExit(f"バンドルID {BUNDLE_ID} が登録されていません")

    certs = [x["id"] for x in asc("get", "/v1/certificates?limit=50")["data"]
             if x["attributes"]["certificateType"] == "DEVELOPMENT"]
    if not certs:
        raise SystemExit("開発用の証明書がありません（Xcodeで作る必要があります）")

    devices = [x["id"] for x in asc("get", "/v1/devices?limit=200")["data"]
               if x["attributes"]["status"] == "ENABLED"]
    print(f"証明書 {len(certs)}件 / 端末 {len(devices)}台 で作ります")

    # 同じ名前の古いものは消す。残しておくと Xcode がどちらを使うか分からなくなる
    for x in asc("get", "/v1/profiles?limit=200")["data"]:
        if x["attributes"]["name"] == PROFILE_NAME:
            asc("delete", f"/v1/profiles/{x['id']}")
            print("古いものを消しました:", x["id"])

    body = json.dumps({"data": {
        "type": "profiles",
        "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_DEVELOPMENT"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle}},
            "certificates": {"data": [{"type": "certificates", "id": c} for c in certs]},
            "devices": {"data": [{"type": "devices", "id": d} for d in devices]},
        }}})
    a = asc("post", "/v1/profiles", body)["data"]["attributes"]

    raw = base64.b64decode(a["profileContent"])
    for folder in ("~/Library/MobileDevice/Provisioning Profiles",
                   "~/Library/Developer/Xcode/UserData/Provisioning Profiles"):
        p = pathlib.Path(os.path.expanduser(folder))
        p.mkdir(parents=True, exist_ok=True)
        (p / f"{a['uuid']}.mobileprovision").write_bytes(raw)

    print(f"✅ {a['name']}（{a['uuid']}）/ 期限 {a['expirationDate'][:10]}")


if __name__ == "__main__":
    main()
