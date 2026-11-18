#!/usr/bin/env python3
"""書き出しの設定（export_presets.cfg）に、スクリプトと素材の暗号化を足す（要件#94。CI だけで使う）。

使い方: python3 tools/enable_encryption.py export_presets.cfg <鍵を組み込んだ Windows のひな形.exe>
鍵そのものは環境変数 GODOT_SCRIPT_ENCRYPTION_KEY で Godot に渡す（このファイルには書かない）。
"""
import re
import sys

PRESET_KEYS = {
    "encryption_include_filters": '"*"',
    "encryption_exclude_filters": '""',
    "encrypt_pck": "true",
    "encrypt_directory": "true",
    "script_export_mode": "2",
}


def set_keys(body: str, keys: dict) -> str:
    for k, v in keys.items():
        line = f"{k}={v}"
        if re.search(rf"^{re.escape(k)}=.*$", body, flags=re.M):
            body = re.sub(rf"^{re.escape(k)}=.*$", lambda _m: line, body, flags=re.M)
        else:
            body = body.rstrip("\n") + "\n" + line + "\n\n"
    return body


def main() -> None:
    path, template = sys.argv[1], sys.argv[2]
    text = open(path, encoding="utf-8").read()
    # [preset.N] と [preset.N.options] の区切りで分ける
    parts = re.split(r"(?m)^(\[preset\.\d+(?:\.options)?\])\s*$", text)
    out = [parts[0]]
    for i in range(1, len(parts), 2):
        head, body = parts[i], parts[i + 1]
        if head.endswith(".options]"):
            body = set_keys(body, {"custom_template/release": '"' + template.replace("\\", "/") + '"'})
        else:
            body = set_keys(body, PRESET_KEYS)
        out.append(head + body)
    open(path, "w", encoding="utf-8").write("".join(out))
    n = len(re.findall(r"(?m)^encrypt_pck=true$", "".join(out)))
    print(f"暗号化を有効にした書き出し設定: {n} 個")
    if n == 0:
        sys.exit("書き出し設定が見つかりません")


if __name__ == "__main__":
    main()
