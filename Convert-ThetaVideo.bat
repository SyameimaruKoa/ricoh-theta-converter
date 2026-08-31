@echo off
rem =========================================================================
rem RICOH THETA 動画一括変換・天頂補正・空間音声バッチ (D&D対応)
rem ※ 詳しい使い方はファイル末尾の :HELP_SECTION をご覧ください。
rem =========================================================================
chcp 932 >nul

rem 引数チェック（ヘルプ指定または引数なし）
if "%~1"=="" goto HELP_SECTION
if "%~1"=="-h" goto HELP_SECTION
if "%~1"=="--help" goto HELP_SECTION
if "%~1"=="/?" goto HELP_SECTION

set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Convert-ThetaVideo.ps1" -Path %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] 変換処理中にエラーが発生しました。
)
echo.
echo 処理が完了しました。Enterキーを押すとウィンドウを閉じます。
pause >nul
exit /b %ERRORLEVEL%

rem =========================================================================
rem ヘルプ表示セクション
rem =========================================================================
:HELP_SECTION
cls
echo =========================================================================
echo    RICOH THETA 完全スタンドアロン動画変換ツール (D^&D対応)
echo =========================================================================
echo.
echo 【概要】
echo   RICOH THETA (THETA V / Z1 等) で撮影した未加工 Dual-Fisheye 動画 (.MP4) を
echo   水平維持・正常な天頂補正・YouTube/VR空間音声 (SA3D内蔵) 対応で
echo   高品質な Equirectangular 形式へ一括変換します。
echo.
echo 【使い方】
echo   1. 変換したい動画ファイル (*.MP4) をこのバッチファイルにドラッグ＆ドロップしてください。
echo.
echo   2. 対話メニューが表示されます（Enter キーを押すだけで推奨設定で開始します）:
echo      - スタビライズ方式: 空間方位固定 (推奨) / カメラ正面追従 / 方位ロック / 手ブレ補正ON
echo      - 正面方位設定    : 開始時基準 / 角度指定 (度) / タイムコード指定 (秒)
echo      - 出力形式        : MOV (YouTube空間音声公式推奨) / MP4
echo      - 音声モード      : PCM (4ch 空間音声 Ambisonics) / ステレオ
echo.
echo   3. 処理内容に応じた識別サフィックスが付与されます:
echo      - 空間方位固定: *_er_spatial.mov
echo      - カメラ追従  : *_er_cam.mov
echo      - 方位ロック  : *_er_lock.mov
echo      - 手ブレ補正ON: *_er.mov
echo.
echo 【コマンドラインでの使用例】
echo   %~nx0 R0010390.MP4
echo   %~nx0 *.MP4
echo   %~nx0 -h
echo.
echo =========================================================================
echo 何かキーを押すと終了します...
pause >nul
exit /b 0
