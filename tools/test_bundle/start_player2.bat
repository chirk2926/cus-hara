@echo off
rem 同じPCでもう1人分のゲームを起動します（対戦を1人で試すとき。セーブとログインは別になります）
cd /d "%~dp0"
start "" CusHara_Test.exe -- --profile=p2
