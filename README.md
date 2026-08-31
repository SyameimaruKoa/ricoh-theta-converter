# RICOH THETA 完全スタンドアロン動画・静止画 一括変換・復元ツール

RICOH THETA（THETA V / Z1 等）で撮影した未加工 Dual-Fisheye 動画および静止画を、**水平維持・正常な天頂補正・YouTube/VR公式空間音声 (SA3D内蔵) 対応・公式サフィックス (_er, _st) 準拠・Googleフォト撮影日時自動復元・RAMDISK 作業領域対応** で高速かつ安全に一括変換・復元するツールです。

---

## 主な機能と特徴

1. **RICOH 公式ツールの完全純正パイプライン（手ブレ補正の映像傾きバグ解消）**
   - RICOH THETA 公式エンジン（`DualfishBlender.exe`）を内蔵。
   - 公式標準のジャイロ天頂補正（`-stabilize:-image`）を使用し、公式アプリの手ブレ補正（SLAM）で発生する「映像が斜めに傾く・揺れる」不具合を解消。

2. **RICOH THETA 公式アプリと完全に同一のサフィックス命名規則**
   - 出力ファイル名は RICOH 公式アプリの処理内容別サフィックスに 100% 準拠しています。
   - **動画 (Equirectangular スティッチ・空間音声)**: `R0010390.MP4` → **`R0010390_er.mov`** / **`R0010390_er.mp4`**
   - **静止画 (スティッチ・水平化補正)**: `R0010390.JPG` → **`R0010390_st.JPG`**

3. **YouTube / Google / VR 空間音声（Ambisonics + SA3D）100% 完全対応**
   - 公式の `RICOH THETA Movie Converter` を用い、YouTube や VR プレイヤーで「頭の向きに合わせて音がリアルタイムに回転する」ために必須となる **`SA3D`（Spatial Audio Box v1）メタデータ** を完全内蔵した公式標準 MOV (PCM 4ch) をデフォルトで生成。

4. **過去に変換してしまった動画を YouTube 空間音声対応 MOV へ一括復元するツール同梱**
   - 既に MP4 等の非対応形式で変換してしまったファイルや未加工動画から、一発で YouTube 空間音声完全対応の MOV ファイルを再生成・復元する **`Restore-ThetaSpatialMov.bat`** を同梱。

5. **RAMDISK（R:\ ドライブ）の自動検出と作業領域の完全 RAM 化（SSD 摩耗ゼロ）**
   - `R:\` ドライブ（RamDisk）がマウントされている場合、中間ファイル（DualfishBlender の一時 MP4/PNG、Movie Converter の作業領域、PowerShell の中間ファイル等）の生成先を自動的に `R:\ThetaTemp` に切り替えます。
   - 大容量の 360度動画変換に伴う SSD への書き込み負荷を完全にゼロにし、SSD の寿命を強力に保護します。

6. **Google フォト JSON からの撮影日時・更新日時 自動復元**
   - Google フォトや Google Takeout からダウンロードした動画・写真は、OS のファイル作成日・更新日がダウンロード日時にリセットされてしまいます。
   - 本ツールは、同一フォルダ内の `<動画名>.json` や EXIF / QuickTime メタデータを自動解析し、**本来の撮影日時にファイルタイムスタンプを完全自動復元** します。

---

## フォルダ構成

```text
ricoh-theta-converter/
├── Convert-ThetaVideo.bat         # 動画・静止画 一括変換 D&D起動バッチ
├── Convert-ThetaVideo.ps1         # 変換メインスクリプト（PowerShell）
├── Restore-ThetaSpatialMov.bat    # YouTube空間音声MOV 復元・再変換バッチ (D&D対応)
├── Restore-ThetaSpatialMov.ps1    # 空間音声MOV 復元メインスクリプト
├── Setup-ThetaTools.bat           # 初回セットアップバッチ
├── Setup-ThetaTools.ps1           # 初回セットアップスクリプト
├── README.md                      # 説明書
└── tools/                         # 自動セットアップされる公式ツール群
    ├── dualfishblender/           # DualfishBlender.exe, ffmpeg 等
    └── ricoh_movie_converter/     # RICOH THETA Movie Converter, Mp4ConverterLib.dll 等
```

---

## 使い方

### 方法 1: 通常変換（ドラッグ＆ドロップ）

1. 変換したい動画（`.MP4` / `.MOV`）や静止画（`.JPG`）を、**`Convert-ThetaVideo.bat`** にドラッグ＆ドロップします。
2. 対話メニューが表示されます（**すべて Enter キーを押すだけで推奨の公式標準 MOV + PCM 4ch 空間音声で即時開始** されます）：
   * **[1] スタビライズ方式:** `1: 空間方位固定` (推奨/デフォルト) / `2: カメラ正面追従` / `3: 方位完全ロック` / `4: 手ブレ補正ON`
   * **[2] 正面方位調整 (任意):** 角度（`90` / `-45`）または タイムコード（`00:00:15` / `15.5`）を入力（省略時: そのまま）
   * **[3] 出力形式 (コンテナ):** `1: MOV (.mov)` (YouTube空間音声公式推奨/デフォルト) / `2: MP4 (.mp4)`
   * **[4] 空間音声形式:** `1: PCM (YouTube空間音声完全対応/デフォルト)` / `2: 通常ステレオ` / `3: 【スーパー非推奨】FLAC`
3. 処理完了後、公式と同じサフィックス付きファイル名（例: **`R0010390_er.mov`** または **`R0010390_st.JPG`**）で出力されます。

### 方法 2: 空間音声 MOV への復元・一括再変換（ドラッグ＆ドロップ）

過去に MP4 等で変換してしまったファイルや生動画を、**YouTube / VR 空間音声（SA3D内蔵）完全対応の公式 MOV へ一発復元** したい場合：
1. ファイルを **`Restore-ThetaSpatialMov.bat`** にドラッグ＆ドロップします。
2. 全自動で元動画から公式 4ch 空間音声を抽出し、**`R0010390_er.mov`** を生成します。

### 方法 3: PowerShell コマンドライン

```powershell
# ヘルプの表示
.\Convert-ThetaVideo.ps1 -h
.\Restore-ThetaSpatialMov.ps1 -h

# 非対話で公式標準 MOV (PCM 4ch 空間音声) 一括変換（R:\ があれば自動でRAMDISK作業）
.\Convert-ThetaVideo.ps1 *.MP4 -NonInteractive

# 変換済み動画から YouTube 空間音声 MOV へ一括復元
.\Restore-ThetaSpatialMov.ps1 *.MP4 -NonInteractive
```

---

## 必要な環境

* **OS:** Windows 10 / 11 (64-bit)
* **RAMDISK (任意/推奨):** `R:\` ドライブをマウントしておくと、自動的に中間作業領域として使用され、SSD への書き込みがゼロになります。
* **PowerShell:** Windows PowerShell 5.1 または PowerShell 7
* **ffmpeg:** パスが通っていること（または `tools/dualfishblender` 内の ffmpeg）
* **exiftool:** （任意）メタデータ復元時に使用
