#!/usr/bin/env python3
"""CI で EOS（Epic Online Services）を組み込む（要件#133）。

GitHub Actions の中だけで使う。リポジトリのファイルは書きかえて commit しない（CI の作業コピーだけ）。

  python3 tools/eos_ci.py cfg      環境変数から config/eos.local.cfg を書く
  python3 tools/eos_ci.py plugin   addons/epic-online-services-godot があれば、project.godot に
                                   自動読み込み（HPlatform など）とプラグインの有効化を足す

環境変数（cfg）:
  EOS_PRODUCT_ID / EOS_SANDBOX_ID / EOS_DEPLOYMENT_ID   GitHub の Variables（秘密ではない ID）
  EOS_CLIENT_ID / EOS_CLIENT_SECRET / EOS_ENCRYPTION_KEY GitHub の Secrets
  EOS_PRODUCT_VERSION                                    任意（既定 1.0.0）

どれかが足りなければ何も書かず、EOS なし（ゲームサーバーのマッチングだけ）で作る。
値はログに出さない。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = "addons/epic-online-services-godot"
AUTOLOADS = [
    ("EOSGRuntime", "runtime.gd"),
    ("HPlatform", "heos/hplatform.gd"),
    ("HAuth", "heos/hauth.gd"),
    ("HAchievements", "heos/hachievements.gd"),
    ("HFriends", "heos/hfriends.gd"),
    ("HStats", "heos/hstats.gd"),
    ("HLeaderboards", "heos/hleaderboards.gd"),
    ("HLobbies", "heos/hlobbies.gd"),
    ("HP2P", "heos/hp2p.gd"),
    ("HSessions", "heos/hsessions.gd"),
]
KEYS = ["EOS_PRODUCT_ID", "EOS_SANDBOX_ID", "EOS_DEPLOYMENT_ID", "EOS_CLIENT_ID", "EOS_CLIENT_SECRET", "EOS_ENCRYPTION_KEY"]
SAFE = re.compile(r"^[A-Za-z0-9._+/=-]{1,200}$")


def write_cfg() -> int:
    vals = {k: os.environ.get(k, "").strip() for k in KEYS}
    missing = [k for k, v in vals.items() if v == ""]
    if missing:
        print(f"::notice::EOS の値が足りないので、EOS なしで作ります（足りない: {', '.join(missing)}）")
        return 0
    for k, v in vals.items():
        if not SAFE.match(v):
            print(f"::error::{k} に使えない文字があります")
            return 1
    if not re.fullmatch(r"[0-9a-fA-F]{64}", vals["EOS_ENCRYPTION_KEY"]):
        print("::error::EOS_ENCRYPTION_KEY は 64 文字の16進数にしてください")
        return 1
    ver = os.environ.get("EOS_PRODUCT_VERSION", "1.0.0").strip() or "1.0.0"
    body = "\n".join([
        "; CI が書いたファイル（tools/eos_ci.py）。commit しない",
        "[eos]",
        'product_name="CusHara"',
        f'product_version="{ver}"',
        f'product_id="{vals["EOS_PRODUCT_ID"]}"',
        f'sandbox_id="{vals["EOS_SANDBOX_ID"]}"',
        f'deployment_id="{vals["EOS_DEPLOYMENT_ID"]}"',
        f'client_id="{vals["EOS_CLIENT_ID"]}"',
        f'client_secret="{vals["EOS_CLIENT_SECRET"]}"',
        f'encryption_key="{vals["EOS_ENCRYPTION_KEY"]}"',
        "",
    ])
    path = os.path.join(ROOT, "config", "eos.local.cfg")
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
    os.chmod(path, 0o600)
    print("config/eos.local.cfg を書きました（値は表示しません）")
    return 0


def enable_plugin() -> int:
    if not os.path.isfile(os.path.join(ROOT, PLUGIN, "plugin.cfg")):
        print("::notice::EOSG プラグインが無いので、EOS なしで作ります")
        return 0
    path = os.path.join(ROOT, "project.godot")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    lines = [f'{name}="*res://{PLUGIN}/{rel}"' for name, rel in AUTOLOADS if f"\n{name}=" not in text]
    if lines:
        text = text.replace("[autoload]\n\n", "[autoload]\n\n" + "\n".join(lines) + "\n", 1)
    if "[editor_plugins]" not in text:
        text = text.rstrip("\n") + f'\n\n[editor_plugins]\n\nenabled=PackedStringArray("res://{PLUGIN}/plugin.cfg")\n'
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"EOSG の自動読み込みを {len(lines)} 個足しました")
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "cfg":
        sys.exit(write_cfg())
    if cmd == "plugin":
        sys.exit(enable_plugin())
    print(__doc__)
    sys.exit(2)
