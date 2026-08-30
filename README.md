# RICOH THETA 完全スタンドアロン動画・静止画 一括変換ツール

RICOH THETA（THETA V / Z1 等）で撮影した未加工 Dual-Fisheye 動画および静止画を、**水平維持・正常な天頂補正・4ch 空間音声展開・Googleフォト撮影日時自動復元・RAMDISK 作業領域対応** で高速かつ安全に一括変換するツールです。

---

## 主な機能と特徴

1. **RICOH 公式エンジンの完全純正パイプライン（手ブレ補正の映像傾きバグ解消）**
   - RICOH THETA 公式エンジン（`DualfishBlender.exe`）を内蔵。
   - 公式標準のジャイロ天頂補正（`-stabilize:-image`）を使用し、公式アプリの手ブレ補正（SLAM）で発生する「映像が斜めに傾く・揺れる」不具合を解消。

2. **RAMDISK（R:\ ドライブ）の自動検出と作業領域の完全 RAM 化（SSD 摩耗ゼロ）**
   - `R:\` ドライブ（RamDisk）がマウントされている場合、中間ファイル（DualfishBlender の一時 MP4/PNG、Movie Converter の作業領域、PowerShell の中間ファイル等）の生成先を自動的に `R:\ThetaTemp` に切り替えます。
   - 大容量の 360度動画変換に伴う SSD への書き込み負荷を完全にゼロにし、SSD の寿命を強力に保護します。

3. **4ch 空間音声（Ambisonics AmbiX + SA3D）の FLAC / PCM 展開**
   - RICOH THETA V / Z1 の 4ch マイクで録音された空間音声メタデータを、公式の `RICOH THETA Movie Converter`（`Mp4ConverterLib.dll`）を用いて正確に展開。
   - 音質劣化ゼロで音声ファイルサイズを約 75% 削減できる **FLAC（可逆圧縮）**、または Movie Converter 標準の **PCM（非圧縮）** を選択可能。

4. **任意の方位角度（ヨー角）または動画タイムコード指定による正面固定**
   - 動画全体の「正面」を任意の角度（例: `90°`, `-45°`, `180°`）に回転オフセット固定可能。
   - また、動画内の特定タイムコード（例: `00:00:15` や `15.5` 秒）を指定することで、**その瞬間に見ている方向を動画全体の「正面（0度）」として固定** できます。

5. **Google フォト JSON からの撮影日時・更新日時 自動復元**
   - Google フォトや Google Takeout からダウンロードした動画・写真は、OS のファイル作成日・更新日がダウンロード日時にリセットされてしまいます。
   - 本ツールは、同一フォルダ内の `<動画名>.json` や EXIF / QuickTime メタデータを自動解析し、**本来の撮影日時にファイルタイムスタンプを完全自動復元** します。

6. **静止画（.JPG）の自動水平化補正**
   - 静止画（.JPG）が渡された場合、THETA V のカメラ固有姿勢オフセット（Pitch: -3.0°, Roll: +3.5°）を解消し、水平な 360度パノラマ写真に自動補正します。

---

## フォルダ構成

```text
ricoh-theta-converter/
├── Convert-ThetaVideo.bat         # ドラッグ＆ドロップ用バッチファイル
├── Convert-ThetaVideo.ps1         # 変換メインスクリプト（PowerShell）
├── Setup-ThetaTools.bat           # 初回セットアップバッチ
├── Setup-ThetaTools.ps1           # 初回セットアップスクリプト
├── README.md                      # 説明書
└── tools/                         # 自動セットアップされる公式ツール群
    ├── dualfishblender/           # DualfishBlender.exe, ffmpeg 等
    └── ricoh_movie_converter/     # RICOH THETA Movie Converter, Mp4ConverterLib.dll 等
```

---

## 使い方

### 方法 1: ドラッグ＆ドロップ（おすすめ）

1. 変換したい動画（`.MP4` / `.MOV`）や静止画（`.JPG`）を、`Convert-ThetaVideo.bat` にまとめてドラッグ＆ドロップします。
2. 動画の場合、対話メニューが表示されます（**すべて Enter キーを押すだけで推奨デフォルト値で即時開始** されます）：
   * **[1] スタビライズ方式:** `1: 空間方位固定` (推奨) / `2: カメラ正面追従` / `3: 方位完全ロック` / `4: 手ブレ補正ON`
   * **[2] 正面方位調整 (任意):** 角度（`90` / `-45`）または タイムコード（`00:00:15` / `15.5`）を入力（省略時: そのまま）
   * **[3] 出力形式 (コンテナ):** `1: MP4 (.mp4)` (推奨) / `2: MOV (.mov)`
   * **[4] 空間音声形式:** `1: FLAC (可逆圧縮 / 容量75%削減)` (推奨) / `2: PCM (非圧縮)` / `3: 通常ステレオ`
3. 処理完了後、`*_corrected.mp4`（動画）または `*_corrected.jpg`（静止画）が元ファイルと同じフォルダに出力されます。

### 方法 2: PowerShell コマンドライン

```powershell
# ヘルプの表示
.\Convert-ThetaVideo.ps1 -h

# 非対話で 4ch FLAC 空間音声 + MP4 一括変換（R:\ ドライブがあれば自動でRAMDISK作業）
.\Convert-ThetaVideo.ps1 *.MP4 -Container MP4 -AudioCodec FLAC -Mode Spatial -NonInteractive

# 正面角度を 90度回転して変換
.\Convert-ThetaVideo.ps1 .\R0010414.MP4 -YawOffset 90 -NonInteractive

# 動画の 15秒時点を正面に固定して変換
.\Convert-ThetaVideo.ps1 *.MP4 -CenterTime "00:00:15" -NonInteractive

# 任意の RAMDISK パスを指定して変換
.\Convert-ThetaVideo.ps1 *.MP4 -TempDir "R:\Temp" -NonInteractive
```

---

## 必要な環境

* **OS:** Windows 10 / 11 (64-bit)
* **RAMDISK (任意/推奨):** `R:\` ドライブをマウントしておくと、自動的に中間作業領域として使用され、SSD への書き込みがゼロになります。
* **PowerShell:** Windows PowerShell 5.1 または PowerShell 7
* **ffmpeg:** パスが通っていること（または `tools/dualfishblender` 内の ffmpeg）
* **exiftool:** （任意）メタデータ復元時に使用
