# RICOH THETA 360度 動画・静止画一括変換ツール (Enhanced DualfishBlender + Spatial Audio)

RICOH THETA（THETA V / Z1 等）で撮影した未加工 Dual-Fisheye 動画および静止画を、**正常な天頂補正（手ブレ補正の傾き不具合の完全解消）**、**4ch 空間音声（First-Order Ambisonics AmbiX + SA3D）の FLAC(可逆圧縮)展開**、**SSD 寿命への配慮（中間書き出しゼロの 1 パス処理）**、および **撮影日時・EXIF メタデータの完全同期** で一括変換する Windows 向け自動化ツールです。

また、**Google フォトからダウンロードした際のメタデータ JSON（`*.json`）からのタイムスタンプ自動復元** にも対応しています。

---

## 🌟 主な特徴 (Key Features)

1. **手ブレ補正による映像の傾き不具合を完全解消**
   * RICOH 公式アプリの手ブレ補正（`image`）は、歩行時の傾きや建造物のパースを誤認して画面が大きく傾いてドリフト固定化する致命的な不具合があります。
   * 本ツールは内部オプション `-stabilize:-image` を適用し、**正確なジャイロ天頂補正＋空間方位固定** を行うことで、HMD（Meta Quest / Apple Vision Pro 等）で見ても一切酔わない完全水平な 4K 360度映像を生成します。
   * カメラ正面追従（`-stabilize:off`）や方位ロック（`-stabilize:lock`）も選択可能です。

2. **Google フォト JSON からの撮影日時・更新日時 自動復元**
   * Google フォトや Google Takeout からダウンロードした動画・写真は、OS のファイル作成日・更新日がダウンロード日時にリセットされてしまいます。
   * 本ツールは、隣接する Google フォト メタデータ JSON（例: `R0010414.MP4.json` / `R0010414.json`）内の `photoTakenTime`、または動画・静止画内の内部メタデータ（EXIF / QuickTime CreateDate）を自動検出し、**ファイルの作成日時・更新日時を撮影当時の真の日時に完全自動復元** します。

3. **4ch 空間音声（AmbiX + SA3D）の FLAC（可逆圧縮）自動展開**
   * THETA V の生データに内包されている 4ch マイク音声を First-Order Ambisonics（AmbiX / ACN順序）空間音声に自動デコード。
   * 音声コーデックに **FLAC（可逆圧縮・ビットパーフェクト）** を標準採用。音質劣化ゼロのまま、従来の非圧縮 WAV/PCM（3072 kbps）から **音声容量を約 75% 削減（約800 kbps）** して軽量化します。
   * **Google フォト対応:** Google フォト、YouTube、Meta Quest、Apple Vision Pro 等で頭の回転に追従する 360度空間オーディオがそのまま再生できます。

4. **SSD 寿命への配慮（巨大中間動画の書き出しゼロ）**
   * 公式手順では「未加工(2GB) → スティッチ(2GB) → 空間音声展開(2GB)」と 2GB 超の巨大ファイルが 3 つ生成され、SSD に 4GB 以上の重複書き込みが発生していました。
   * 本ツールは映像スティッチと音声展開をメモリ／一時パイプラインで直結し、**SSD への書き込みを「最終完成品（2GB）の 1 回のみ」** に集約します。

5. **静止画（.JPG）の自動水平補正**
   * 加速度センサーのゼロ点校正誤差等による静止画の微妙な傾き（Pitch / Roll オフセット）を自動補正し、完全水平な 360度パノラマ写真を生成します。

6. **作成日・更新日・EXIF 撮影日時の完全同期**
   * Google フォトやクラウドストレージで撮影順に正しく並ぶよう、ファイルシステムのタイムスタンプ（作成日時・更新日時）および EXIF/XMP メタデータを元ファイルと完全に一致させます。

7. **ドラッグ＆ドロップ（D&D）対応・対話型メニュー**
   * バッチファイルにファイルを放り込むだけで、GUI なしで即座に一括処理が可能です。

---

## 🛠️ 前提条件 (Prerequisites)

* **OS:** Windows 10 / 11 (64-bit)
* **外部ツール (PATH が通っていること):**
  * `ffmpeg` (映像・音声結合用)
  * `exiftool` (メタデータ同期用)
  * `7z` または `7za` (セットアップ時の自動展開用 / 7-Zip や NanaZip 等)

---

## 📦 セットアップ方法 (Setup)

※ 本リポジトリには著作権・ライセンス保護のため、RICOH 社のプロプライエタリなバイナリ（`DualfishBlender.exe`, `Mp4ConverterLib.dll` 等）は含まれていません。

### 手順（全自動抽出）
1. 以下のいずれか（または両方）の RICOH 公式インストーラーをダウンロードし、本プロジェクトフォルダ（または `Downloads` フォルダ）に配置します：
   * **`RICOH THETA Setup.exe`** (パソコン用基本アプリ インストーラー)
   * **`RICOH_THETA_Movie_Converter_ja.zip`** (RICOH THETA Movie Converter)
   * ※ すでに PC に RICOH THETA アプリがインストールされている場合は、インストーラー不要で自動コピーされます。
2. **`Setup-ThetaTools.bat`** をダブルクリックして実行します。
3. インストーラーから必要な変換バイナリのみが自動抽出され、`tools/` フォルダ配下にポータブル環境が構築されます。

---

## 🚀 使い方 (Usage)

### 方法 1: ドラッグ＆ドロップ (おすすめ)
1. 変換したい未加工動画（`.MP4` / `.MOV`）または静止画（`.JPG`）を **`Convert-ThetaVideo.bat`** にドラッグ＆ドロップします（複数ファイル選択可）。
   * ※ Google フォトの `.json` ファイルが同じフォルダにある場合、自動的に撮影日時が復元されます。
2. 動画の場合、対話メニューが表示されます（**すべて Enter キーを押すだけで推奨デフォルト値で即時開始** されます）：
   * **[1] スタビライズ方式:** `1: 空間方位固定 [-stabilize:-image]` (推奨) / `2: カメラ正面追従` / `3: 方位ロック`
   * **[2] 出力コーデック:** `1: H.264 (AVC)` (推奨) / `2: H.265 (HEVC)`
   * **[3] コンテナ形式:** `1: MP4 (.mp4)` (推奨) / `2: MOV (.mov)`
   * **[4] 空間音声形式:** `1: FLAC (可逆圧縮 / 容量75%削減)` (推奨) / `2: PCM (非圧縮)` / `3: 通常ステレオ`
   * **[5] エンコーダー:** `1: GPU自動検出` / `2: NVIDIA NVENC` / `3: Intel QSV` / `4: CPU`
3. 処理完了後、`*_corrected.mp4`（動画）または `*_corrected.jpg`（静止画）が元ファイルと同じフォルダに出力されます。

### 方法 2: PowerShell コマンドライン
```powershell
# ヘルプの表示
.\Convert-ThetaVideo.ps1 -h

# 非対話で 4ch FLAC 空間音声 + MP4 + H.265 一括変換
.\Convert-ThetaVideo.ps1 *.MP4 -Container MP4 -AudioCodec FLAC -Mode Spatial -Codec H265 -NonInteractive

# 静止画の自動水平補正
.\Convert-ThetaVideo.ps1 *.JPG -NonInteractive
```

---

## 📁 リポジトリ構造 (Repository Structure)

```text
ricoh-theta-converter/
├── Convert-ThetaVideo.bat     # 動画・静止画 一括変換 D&D起動バッチ (Shift-JIS)
├── Convert-ThetaVideo.ps1     # 変換メインスクリプト (UTF-8 BOM)
├── Setup-ThetaTools.bat       # バイナリ自動抽出・セットアップ起動バッチ (Shift-JIS)
├── Setup-ThetaTools.ps1       # セットアップ処理スクリプト (UTF-8 BOM)
├── .gitignore                 # プロプライエタリバイナリ除外設定
├── LICENSE                    # MIT License
└── README.md                  # 本ドキュメント
```

---

## 📄 ライセンス (License)

本プロジェクトのスクリプトコードは [MIT License](LICENSE) の下で公開されています。

> **免責事項 (Disclaimer):**  
> 本ツールは RICOH 社の公式ソフトウェアではありません。RICOH, THETA は株式会社リコーの登録商標です。  
> 抽出・利用される各ツールのバイナリ（`DualfishBlender.exe`, `RICOH THETA Movie Converter.exe` 等）の著作権は株式会社リコーに帰属します。
