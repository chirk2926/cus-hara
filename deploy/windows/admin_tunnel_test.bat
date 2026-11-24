@echo off
rem テスト環境の管理画面（127.0.0.1:8791）を開く。SERVER= は admin_tunnel.bat の方を書きかえる（要件#118）
call "%~dp0admin_tunnel.bat" test
