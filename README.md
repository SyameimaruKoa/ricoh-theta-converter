# RICOH THETA 完全スタンドアロン動画 一括変換・復元ツール

RICOH THETA（THETA V / Z1 等）で撮影した未加工 Dual-Fisheye 動画を、**水平維持・正常な天頂補正・YouTube/VR公式空間音声 (SA3D内蔵) 対応・処理内容別完全識別サフィックス・Googleフォト撮影日時自動復元・RAMDISK 作業領域対応** で高速かつ安全に一括変換・復元するツールです。

---

## 主な機能と特徴

1. **処理内容・機能が一目で判別できる完全識別サフィックス体系**
   - ファイル名を見ただけで「どのスタビライズ方式・方位固定・回転オフセットが適用されたか」を 100% 確実に判別できます。
   
   | 処理内容・機能 | 出力ファイル名サフィックス（例: R0010390.MP4） | 説明 |
   | :--- | :--- | :--- |
   | **公式標準手ブレ補正ON** | `R0010390_er.mov` / `.mp4` | 公式基本アプリ互換（ジャイロ天頂補正＋手ブレ補正） |
   | **空間方位固定 (推奨)** | `R0010390_er_spatial.mov` / `.mp4` | ジャイロ天頂補正＋空間方位固定（手ブレ補正OFF） |
   | **カメラ正面追従** | `R0010390_er_cam.mov` / `.mp4` | ジャイロ天頂補正＋カメラレンズ正面追従 |
   | **方位完全ロック** | `R0010390_er_lock.mov` / `.mp4` | ジャイロ天頂補正＋撮影開始時の方位完全固定 |
   | **正面方位回転オフセット** | `R0010390_er_spatial_yaw90.mov` | ヨー角（角度）を指定して正面を回転固定 |
   | **タイムコード正面指定** | `R0010390_er_spatial_tc000015.mov` | 指定秒数の時点を動画全体の正面に固定 |

2. **RICOH 公式エンジンの完全純正パイプライン（手ブレ補正の映像傾きバグ解消）**
   - RICOH THETA 公式エンジン（`DualfishBlender.exe`）を内蔵。
   - 手ブレ補正の映像傾きバグのない高品質なスティッチングを実現。

3. **YouTube / Google / VR 空間音声（Ambisonics + SA3D）100% 完全対応**
   - 公式の `RICOH THETA Movie Converter` を用い、YouTube や VR プレイヤーで「頭の向きに合わせて音がリアルタイムに回転する」ために必須となる **`SA3D`（Spatial Audio Box v1）メタデータ** を完全内蔵した公式標準 MOV (PCM 4ch) をデフォルトで生成。

4. **過去に変換してしまった動画を YouTube 空間音声対応 MOV へ一括復元するツール同梱**
   - 既に MP4 等の非対応形式で変換してしまったファイルや未加工動画から、一発で YouTube 空間音声完全対応の MOV ファイルを再生成・復元する **`Restore-ThetaSpatialMov.bat`** を同梱。

5. **RAMDISK（R:\ ドライブ）の自動検出と作業領域の完全 RAM 化（SSD 摩耗ゼロ）**
   - `R:\` ドライブ（RamDisk）がマウントされている場合、中間ファイルの生成先を自動的に `R:\ThetaTemp` に切り替えます。
   - 大容量の 360度動画変換に伴う SSD への書き込み負荷を完全にゼロにし、SSD の寿命を強力に保護します。

6. **Google フォト JSON からの撮影日時・更新日時 自動復元**
   - Google フォトや Google Takeout からダウンロードした動画は、OS のファイル作成日・更新日がリセットされてしまいますが、同一フォルダ内の `<動画名>.json` や EXIF / QuickTime メタデータから **本来の撮影日時にファイルタイムスタンプを完全自動復元** します。

---

## フォルダ構成

```text
ricoh-theta-converter/
├── Convert-ThetaVideo.bat         # 動画一括変換 D&D起動バッチ
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

1. 変換したい動画（`.MP4` / `.MOV`）を、**`Convert-ThetaVideo.bat`** にドラッグ＆ドロップします。
2. 対話メニューが表示されます（**すべて Enter キーを押すだけで推奨の空間方位固定 MOV + PCM 4ch 空間音声で即時開始** されます）：
   * **[1] スタビライズ方式:** `1: 空間方位固定 [_er_spatial]` (推奨/デフォルト) / `2: カメラ正面追従 [_er_cam]` / `3: 方位完全ロック [_er_lock]` / `4: 手ブレ補正ON [_er]`
   * **[2] 正面方位調整 (任意):** 角度（`90` / `-45`）または タイムコード（`00:00:15` / `15.5`）を入力（省略時: そのまま）
   * **[3] 出力形式 (コンテナ):** `1: MOV (.mov)` (YouTube空間音声公式推奨/デフォルト) / `2: MP4 (.mp4)`
   * **[4] 空間音声形式:** `1: PCM (YouTube空間音声完全対応/デフォルト)` / `2: 通常ステレオ` / `3: 【スーパー非推奨】FLAC`
3. 処理完了後、処理内容に応じた識別サフィックス付きファイル名（例: **`R0010390_er_spatial.mov`**）で出力されます。

### 方法 2: 空間音声 MOV への復元・一括再変換（ドラッグ＆ドロップ）

過去に MP4 等で変換してしまったファイルや生動画を、**YouTube / VR 空間音声（SA3D内蔵）完全対応の公式 MOV へ一発復元** したい場合：
1. ファイルを **`Restore-ThetaSpatialMov.bat`** にドラッグ＆ドロップします。
2. 全自動で元動画から公式 4ch 空間音声を抽出し、**`R0010390_er_spatial.mov`** を生成します。

### 方法 3: PowerShell コマンドライン

```powershell
# ヘルプの表示
.\Convert-ThetaVideo.ps1 -h
.\Restore-ThetaSpatialMov.ps1 -h

# 非対話で空間方位固定 MOV (PCM 4ch 空間音声) 一括変換（R:\ があれば自動でRAMDISK作業）
.\Convert-ThetaVideo.ps1 *.MP4 -NonInteractive

# カメラ正面追従モードで一括変換
.\Convert-ThetaVideo.ps1 *.MP4 -Mode Camera -NonInteractive

# 正面角度を 90度回転して変換
.\Convert-ThetaVideo.ps1 .\R0010414.MP4 -YawOffset 90 -NonInteractive
```

---

## 必要な環境

* **OS:** Windows 10 / 11 (64-bit)
* **RAMDISK (任意/推奨):** `R:\` ドライブをマウントしておくと、自動的に中間作業領域として使用され、SSD への書き込みがゼロになります。
* **PowerShell:** Windows PowerShell 5.1 または PowerShell 7
* **ffmpeg:** パスが通っていること（または `tools/dualfishblender` 内の ffmpeg）
* **exiftool:** （任意）メタデータ復元時に使用
