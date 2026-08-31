@echo off
rem =========================================================================
rem RICOH THETA 空間音声MOV (SA3D内蔵) 復元・再変換バッチ (D&D対応)
rem ※ 詳しい使い方はファイル末尾の :HELP_SECTION をご覧ください。
rem =========================================================================
chcp 932 >nul

rem 引数チェック（ヘルプ指定または引数なし）
if "%~1"=="" goto HELP_SECTION
if "%~1"=="-h" goto HELP_SECTION
if "%~1"=="--help" goto HELP_SECTION
if "%~1"=="/?" goto HELP_SECTION

set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Restore-ThetaSpatialMov.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] 処理中にエラーが発生しました。
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
echo    RICOH THETA 空間音声MOV (SA3D内蔵) 復元・再変換ツール (D^&D対応)
echo =========================================================================
echo.
echo 【概要】
echo   MP4等の形式で変換してしまったRICOH THETA動画や未加工動画 (*.MP4) を、
echo   YouTube や VR プレイヤーで 100%% 空間オーディオとして自動認識される
echo   公式標準 MOV (PCM 4ch + SA3D内蔵) 形式へ復元・変換します。
echo.
echo 【使い方】
echo   1. 変換したいファイル (*.MP4) をこのバッチファイルにドラッグ＆ドロップしてください。
echo      (複数ファイルの一括ドロップに対応しています)
echo.
echo   2. RAMDISK (R:\ ドライブ) がマウントされている場合、自動的に作業領域
echo      として使用され、SSD への書き込み負荷はゼロになります。
echo.
echo   3. 撮影日時・更新日時も Google フォト JSON や EXIF から完全自動復元されます。
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
