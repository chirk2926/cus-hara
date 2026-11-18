@echo off
chcp 65001 > nul
rem テスト用のゲームサーバーを起動します（Node.js 22.18 以上が必要）。
rem AI のキーが無いときは、キーワード判定で動きます。止めるときはこの窓を閉じてください。
cd /d "%~dp0server"
where node > nul 2>&1
if errorlevel 1 (
  echo Node.js が見つかりません。https://nodejs.org/ から LTS 版（22 以上）を入れてください。
  pause
  exit /b 1
)
set PORT=8787
set LLM_MODE=offline
set STT_PROVIDER=mock
set ALLOW_SAME_IP_RANKED=1
node --disable-warning=ExperimentalWarning src/main.ts
pause
