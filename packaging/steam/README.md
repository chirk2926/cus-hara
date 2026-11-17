# Steam 用のアップロード設定

1. GitHub Actions の成果物 `CusHara-windows`（`CusHara.exe`）を、このフォルダの `content/` に置く。
2. `app_build.vdf` のアプリIDとデポIDを自分のものに書き換える。
3. Steamworks SDK の `steamcmd` で次を実行する。

```bash
steamcmd +login <アカウント名> +run_app_build <app_build.vdf の絶対パス> +quit
```

4. Steamworks の管理画面で、アップロードされたビルドをブランチ（default など）に設定する。
5. 起動オプションの実行ファイルは `CusHara.exe`。

対戦モードのSteam招待・マッチングを使うには、GodotSteam（GDExtension）を `addons/godotsteam/` に入れてから
exe を作り直す必要がある。詳しくは `docs/MAINTENANCE.md` の「Steam で配布する」を参照。

`content/` と `output/` は Git に入れない（`.gitignore` 済み）。
