@echo off
rem ============================================================
rem RICOH THETA 変換エンジン自動セットアップ起動バッチ
rem 使い方・ヘルプは本ファイルの末尾に記載されています。
rem ============================================================
chcp 932 >nul

rem ヘルプ引数の判定
if "%~1"=="-h" goto :show_help
if "%~1"=="--help" goto :show_help
if "%~1"=="/?" goto :show_help

rem PowerShell スクリプトを実行
set PS_SCRIPT=%~dp0Setup-ThetaTools.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*

echo.
echo 処理が完了しました。Enterキーを押すとウィンドウを閉じます。
pause >nul
exit /b 0

:show_help
rem ============================================================
rem ヘルプ表示セクション
rem ============================================================
echo ============================================================
echo   RICOH THETA 変換エンジン自動セットアップツール
echo ============================================================
echo.
echo 【概要】
echo   RICOH 公式インストーラーから動画変換・空間音声に必要なバイナリのみを
echo   自動抽出し、ポータブルな tools/ 環境を構築します。
echo.
echo 【必要なファイル】
echo   以下のいずれか、または両方を本バッチと同じフォルダ（または Downloads）
echo   に配置して本バッチをダブルクリックしてください：
echo     1. RICOH THETA Setup.exe (PC基本アプリ インストーラー)
echo     2. RICOH_THETA_Movie_Converter_ja.zip (空間音声コンバーター)
echo.
echo   ※ すでに PC に RICOH THETA アプリがインストールされている場合は、
echo      自動的にそこから必要ファイルをコピーします。
echo ============================================================
echo.
echo 何かキーを押すとウィンドウを閉じます...
pause >nul
exit /b 0
