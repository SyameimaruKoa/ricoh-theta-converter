@echo off
rem ============================================================
rem RICOH THETA 動画・静止画一括変換ドラッグ＆ドロップ起動バッチ
rem 使い方・ヘルプは本ファイルの末尾に記載されています。
rem ============================================================
chcp 932 >nul

rem 引数チェック（未引数の場合はヘルプを表示して一時停止）
if "%~1"=="" goto :show_help

rem PowerShell スクリプトを実行
set PS_SCRIPT=%~dp0Convert-ThetaVideo.ps1
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
echo   RICOH THETA 動画・静止画一括変換ツール (D^&D対応)
echo ============================================================
echo.
echo 【使い方】
echo   1. 変換したい RICOH THETA の動画 (.MP4) または 静止画 (.JPG) を
echo      このバッチファイル (Convert-ThetaVideo.bat) に
echo      ドラッグ＆ドロップしてください。(複数ファイル一括可)
echo.
echo   2. 動画の場合、画面に対話型メニューが表示されます：
echo      - スタビライズ方式 (空間固定 / カメラ追従 / ロック)
echo      - コーデック (H.264 / H.265)
echo      - 出力形式 (MP4 / MOV)
echo      - 空間音声コーデック (FLAC可逆圧縮 / PCM非圧縮)
echo      - エンコーダー (GPU自動 / NVENC / QSV / CPU)
echo      を選択 (Enter連打で推奨設定) すると一括処理が始まります。
echo.
echo   3. 変換後ファイル (*_corrected.mp4 / *_corrected.mov / *_corrected.jpg)
echo      が生成され、作成日・更新日・撮影日時が元ファイルと完全同期されます。
echo.
echo   ※ FLAC (可逆圧縮) は MP4 / MOV の両方に対応し、Googleフォトでも
echo      完全サポートされています。音質劣化ゼロで音声容量を約75%削減します。
echo   ※ SSD寿命に配慮し、中間巨大動画ファイルは一切SSDに残さず
echo      最終完成ファイルのみを1回で出力します。
echo ============================================================
echo.
echo 何かキーを押すとウィンドウを閉じます...
pause >nul
exit /b 0
