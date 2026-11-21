@echo off
chcp 65001 >nul
rem カスハラ防衛線の管理画面を、家の Windows PC から開く（docs/HOME_SERVER.md）。
rem サーバーの管理画面は、サーバーのマシンの中（127.0.0.1:8790）でしか開けない。
rem SSH のトンネルで、この PC の 127.0.0.1:8790 をサーバーの 127.0.0.1:8790 につなぐ。
rem ↓ 自分のサーバーのユーザー名と、家の中でのアドレス（例 192.168.1.20）に書きかえる
set SERVER=cushara@192.168.1.20

echo 管理画面につないでいます。終わったらこの窓を閉じてください。
rem トンネルがつながってからブラウザを開く（先に開くとつながらない画面になる）。パスワードを入れている間も待つ
start "" /min powershell -NoProfile -WindowStyle Hidden -Command "for($i=0;$i -lt 300;$i++){try{$c=New-Object Net.Sockets.TcpClient('127.0.0.1',8790);$c.Close();Start-Process 'http://127.0.0.1:8790/';break}catch{Start-Sleep 1}}"
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8790:127.0.0.1:8790 %SERVER%
pause
