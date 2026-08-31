<#
.SYNOPSIS
    RICOH THETAの未加工動画・静止画を対話型設定・正常な天頂補正・4ch空間音声(SA3D内蔵MOV/PCM)展開・任意方位固定で一括変換します。

.DESCRIPTION
    RICOH THETA公式エンジン（DualfishBlender.exe）および公式空間音声エンジン（RICOH THETA Movie Converter）の
    純正パイプラインを100%そのまま使用し、YouTubeやVRプレイヤーで確実に360度空間音声（Ambisonics SA3D）として認識される
    高品質なEquirectangular動画を生成します。
    
    【処理内容別ファイル名サフィックス規則】
    どのような処理が行われたかがファイル名だけで完全に判別・区別できるように自動命名されます：
      - 公式標準手ブレ補正ON   : *_er.mov / *_er.mp4
      - 空間方位固定 (推奨)     : *_er_spatial.mov / *_er_spatial.mp4
      - カメラ正面追従         : *_er_cam.mov / *_er_cam.mp4
      - 方位完全ロック         : *_er_lock.mov / *_er_lock.mp4
      - 正面方位回転あり       : *_er_spatial_yaw90.mov / *_er_cam_yaw-45.mov
      - タイムコード正面指定   : *_er_spatial_tc000015.mov
      - 静止画水平補正         : *_st.jpg / *_st_yaw90.jpg

    RAMDISK（R:\ 等）の自動検出と中間作業領域の完全RAM化に対応し、SSD書き込み寿命を強力に保護します。
    公式標準の MOV (PCM 4ch + SA3D内蔵) を最優先推奨・デフォルトとし、
    GoogleフォトのメタデータJSON (例: *.MP4.json) や EXIF/QuickTime メタデータからの撮影日時・タイムスタンプ完全自動復元に対応しています。

.PARAMETER Path
    変換対象のRICOH THETA未加工動画・静止画ファイルパス（複数指定、ワイルドカード、パイプライン対応）。

.PARAMETER Mode
    スタビライズ・方位固定モード（Spatial: 空間方位固定 / Camera: カメラ正面追従 / Lock: 方位ロック / ImageBlur: 手ブレ補正ON）。

.PARAMETER Container
    出力コンテナ形式（MOV: YouTube/VR空間音声公式推奨 / MP4: 汎用）。

.PARAMETER AudioCodec
    音声コーデック（PCM: YouTube/VR空間音声公式標準 / FLAC: 非推奨・ローカル保存用 / Stereo: 通常ステレオ）。

.PARAMETER YawOffset
    動画全体の正面方向（ヨー角）オフセット（度、例: 90, -45, 180）。

.PARAMETER CenterTime
    動画内で「正面」としたいタイムコード（例: "00:01:20" または "15.5" 秒）。

.PARAMETER OutputDir
    出力先ディレクトリ（省略時は元ファイルと同じフォルダ）。

.PARAMETER TempDir
    中間ファイル作成用の一時ディレクトリ（RAMDISKなど。省略時は R:\ ドライブが存在すれば自動使用、なければシステムTEMP）。

.PARAMETER NonInteractive
    対話プロンプトを表示せず、指定されたパラメータ（またはデフォルト値）で即時実行します。

.PARAMETER Help
    ヘルプ情報を表示します（-h または --help）。

.EXAMPLE
    .\Convert-ThetaVideo.ps1 -Path .\R0010414.MP4

.EXAMPLE
    .\Convert-ThetaVideo.ps1 *.MP4 -Mode Spatial -Container MOV -AudioCodec PCM -NonInteractive

.EXAMPLE
    .\Convert-ThetaVideo.ps1 *.MP4 -CenterTime "00:00:15" -NonInteractive

.EXAMPLE
    .\Convert-ThetaVideo.ps1 -h
#>
[CmdletBinding()]
param (
    #region Parameters
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Path,

    [ValidateSet('Spatial', 'Camera', 'Lock', 'ImageBlur')]
    [string]$Mode,

    [ValidateSet('MOV', 'MP4')]
    [string]$Container,

    [ValidateSet('PCM', 'FLAC', 'Stereo')]
    [string]$AudioCodec,

    [double]$YawOffset = 0.0,

    [string]$CenterTime,

    [string]$OutputDir,

    [string]$TempDir,

    [switch]$NonInteractive,

    [Alias('h', '-help')]
    [switch]$Help
    #endregion
)

#region Help Handling
if ($Help -or (-not $Path -and -not $NonInteractive)) {
    Get-Help -Name $PSCommandPath -Full
    exit 0
}
#endregion

#region Set GPU Performance Environment Flags (dGPU Optimization)
$env:SHIM_MCCOMPAT = "0x0000000000000001"
$env:CUDA_VISIBLE_DEVICES = "0"
$env:__NV_PRIME_RENDER_OFFLOAD = "1"
#endregion

#region Setup RAMDISK / Working Temp Directory (Zero SSD Wear)
$workingTempDir = ""
$isRamDisk = $false

if ($TempDir -and (Test-Path $TempDir)) {
    $workingTempDir = (Resolve-Path $TempDir).Path
} elseif (Test-Path "R:\") {
    $workingTempDir = "R:\ThetaTemp"
    $isRamDisk = $true
} else {
    $workingTempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ThetaTemp")
}

if (-not (Test-Path $workingTempDir)) {
    New-Item -Path $workingTempDir -ItemType Directory -Force | Out-Null
}

# Redirect process-level TEMP and TMP so DualfishBlender, ffmpeg, and Movie Converter use RAMDISK
$env:TEMP = $workingTempDir
$env:TMP = $workingTempDir

$tempFreeGb = 0.0
try {
    $driveLetter = $workingTempDir.Substring(0, 1)
    $drv = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
    if ($drv) {
        $tempFreeGb = [Math]::Round($drv.Free / 1GB, 1)
    }
} catch { }

$tempDisplayStr = "$workingTempDir $(if ($isRamDisk) { '(RAMDISK 検出・SSD書き込み完全ゼロ)' }) [空き: ${tempFreeGb} GB]"
#endregion

#region Engine Discovery and Environment Detection
$scriptDir = Split-Path -Parent $PSCommandPath

# 1. DualfishBlender path (Prefer local embedded tools, fallback to installed AppData)
$localBlender = Join-Path $scriptDir "tools\dualfishblender\DualfishBlender.exe"
$appDataBlender = Join-Path $env:LOCALAPPDATA "Programs\RicohTheta\resources\tools\dualfishblender\win\DualfishBlender.exe"

if (Test-Path $localBlender) {
    $blenderPath = $localBlender
    $resourcesPath = Join-Path $scriptDir "tools\dualfishblender"
} elseif (Test-Path $appDataBlender) {
    $blenderPath = $appDataBlender
    $resourcesPath = [System.IO.Path]::GetDirectoryName((Split-Path -Parent $blenderPath))
} else {
    Write-Error "DualfishBlender.exe が見つかりません。Setup-ThetaTools.bat を実行してセットアップを行ってください。"
    exit 1
}

# 2. RICOH THETA Movie Converter path (Official spatial audio engine)
$movieConverterDir = Join-Path $scriptDir "tools\ricoh_movie_converter"
$hasMovieConverter = (Test-Path (Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe")) -and (Test-Path (Join-Path $movieConverterDir "Mp4ConverterLib.dll"))

# 3. Detect all GPUs on the system (dGPU + iGPU)
$gpuList = [System.Collections.Generic.List[string]]::new()
try {
    $controllers = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($c in $controllers) {
        if ($c.Name -and $c.Name -notmatch "Basic Display|Miracast") {
            $gpuList.Add($c.Name)
        }
    }
} catch { }

# 4. Check DualfishBlender showCapability
$detectedGpu = "Auto"
try {
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $blenderPath
    $pinfo.Arguments = "-showCapability"
    $pinfo.WorkingDirectory = $resourcesPath
    $pinfo.UseShellExecute = $false
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($pinfo)
    $capOut = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    if ($capOut -match "OpenGLRenderer:\s*'([^']+)'") {
        $detectedGpu = $matches[1]
    }
} catch {
    $detectedGpu = "Auto"
}

$gpuDisplayStr = if ($gpuList.Count -gt 0) { $gpuList -join " / " } else { $detectedGpu }
#endregion

#region Timestamp Extraction Helper (Google Photos JSON & Metadata)
function Get-MediaTrueTimestamp {
    param (
        [string]$FilePath
    )
    $fileItem = Get-Item $FilePath
    $dir = $fileItem.DirectoryName
    $name = $fileItem.Name
    $cleanRegex = '(_er|_st|_spatial|_cam|_lock|_yaw[0-9\-]+|_tc[0-9\-]+|_corrected|_stitched)+$'
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($name) -replace $cleanRegex, ''

    # 1. Search Google Photos JSON files: <name>.json, <name>.MP4.json, <nameWithoutExt>.json
    $jsonCandidates = @(
        (Join-Path $dir "$name.json"),
        (Join-Path $dir "$nameWithoutExt.json"),
        (Join-Path $dir "$nameWithoutExt.MP4.json"),
        (Join-Path $dir "$nameWithoutExt.JPG.json"),
        (Join-Path $dir "$nameWithoutExt.MOV.json")
    )
    foreach ($jc in $jsonCandidates) {
        if (Test-Path $jc) {
            try {
                $jsonContent = Get-Content -Path $jc -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($jsonContent.photoTakenTime -and $jsonContent.photoTakenTime.timestamp) {
                    $tsLong = [int64]$jsonContent.photoTakenTime.timestamp
                    if ($tsLong -gt 0) {
                        $dt = [System.DateTimeOffset]::FromUnixTimeSeconds($tsLong).LocalDateTime
                        return @{ DateTime = $dt; Source = "GooglePhotosJSON ($([System.IO.Path]::GetFileName($jc)))" }
                    }
                }
                if ($jsonContent.creationTime -and $jsonContent.creationTime.timestamp) {
                    $tsLong = [int64]$jsonContent.creationTime.timestamp
                    if ($tsLong -gt 0) {
                        $dt = [System.DateTimeOffset]::FromUnixTimeSeconds($tsLong).LocalDateTime
                        return @{ DateTime = $dt; Source = "GooglePhotosJSON ($([System.IO.Path]::GetFileName($jc)))" }
                    }
                }
            } catch { }
        }
    }

    # 2. Search internal EXIF / QuickTime CreateDate via exiftool
    try {
        $exifDate = (exiftool -d "%Y:%m:%d %H:%M:%S" -s3 -DateTimeOriginal -CreateDate -CreationDate -TrackCreateDate "$FilePath" 2>$null | Where-Object { $_ -match "^\d{4}:\d{2}:\d{2}" } | Select-Object -First 1)
        if ($exifDate -and ($exifDate -match "^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})")) {
            $parsedDt = [datetime]::ParseExact($exifDate.Trim(), "yyyy:MM:dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            return @{ DateTime = $parsedDt; Source = "InternalMetadata (EXIF/QuickTime)" }
        }
    } catch { }

    # 3. Fallback to file system LastWriteTime
    return @{ DateTime = $fileItem.LastWriteTime; Source = "FileSystem" }
}
#endregion

#region Collect Input Files
$inputFiles = [System.Collections.Generic.List[string]]::new()
if ($Path) {
    foreach ($p in $Path) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $resolved = @(Resolve-Path -Path $p -ErrorAction SilentlyContinue)
        if ($resolved.Count -gt 0) {
            foreach ($r in $resolved) {
                if (Test-Path -Path $r.Path -PathType Leaf) {
                    $inputFiles.Add($r.Path)
                }
            }
        } elseif (Test-Path -Path $p -PathType Leaf) {
            $inputFiles.Add((Get-Item $p).FullName)
        }
    }
}

if ($inputFiles.Count -eq 0) {
    Write-Host "処理対象の動画または静止画ファイルが指定されていません。" -ForegroundColor Yellow
    Get-Help -Name $PSCommandPath -Full
    exit 0
}

$videoFiles = [System.Collections.Generic.List[string]]::new()
$imageFiles = [System.Collections.Generic.List[string]]::new()

foreach ($f in $inputFiles) {
    $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
    if ($ext -in '.mp4', '.mov') {
        $videoFiles.Add($f)
    } elseif ($ext -in '.jpg', '.jpeg') {
        $imageFiles.Add($f)
    }
}
#endregion

#region Interactive Menu
if (-not $NonInteractive -and $videoFiles.Count -gt 0 -and ([string]::IsNullOrWhiteSpace($Mode) -or [string]::IsNullOrWhiteSpace($Container) -or [string]::IsNullOrWhiteSpace($AudioCodec))) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "        RICOH THETA 完全スタンドアロン一括変換ツール        " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "動画ファイル: $($videoFiles.Count) 件, 静止画ファイル: $($imageFiles.Count) 件" -ForegroundColor White
    foreach ($f in $inputFiles) {
        Write-Host "  - $([System.IO.Path]::GetFileName($f))" -ForegroundColor Gray
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "作業領域 (TEMP)        : $tempDisplayStr" -ForegroundColor Green
    Write-Host "搭載GPU構成            : $gpuDisplayStr" -ForegroundColor Green
    Write-Host "映像スティッチエンジン : 内蔵 (DualfishBlender 公式純正)" -ForegroundColor Green
    Write-Host "空間音声エンジン       : $(if ($hasMovieConverter) { '内蔵 (RICOH THETA Movie Converter 公式純正)' } else { '未検出 (ステレオのみ)' })" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    # 1. Mode selection
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        Write-Host "`n[1] スタビライズ / 方位固定モードを選択してください:" -ForegroundColor Yellow
        Write-Host "  1: 空間方位固定 (ジャイロ天頂補正 + 空間方位固定, 画像ブレ補正OFF) [_er_spatial] [推奨/デフォルト]"
        Write-Host "  2: カメラ正面追従 (ジャイロ天頂補正 + カメラレンズ正面追従) [_er_cam]"
        Write-Host "  3: 方位完全ロック (ジャイロ天頂補正 + 撮影開始時の方位完全ロック) [_er_lock]"
        Write-Host "  4: 手ブレ補正ON (公式標準: ジャイロ天頂補正 + 画像認識手ブレ補正) [_er]"
        $modeChoice = Read-Host "選択 [1-4] (デフォルト: 1)"
        switch ($modeChoice.Trim()) {
            '2' { $Mode = 'Camera' }
            '3' { $Mode = 'Lock' }
            '4' { $Mode = 'ImageBlur' }
            default { $Mode = 'Spatial' }
        }
    }

    # 2. Yaw Offset / Center Time selection
    if ($YawOffset -eq 0.0 -and [string]::IsNullOrWhiteSpace($CenterTime)) {
        Write-Host "`n[2] 正面方位（ヨー角）の調整 (任意):" -ForegroundColor Yellow
        Write-Host "  - 開始時の正面のままで良い場合は そのまま Enter"
        Write-Host "  - 角度で指定する場合: 90, -45, 180 などを入力"
        Write-Host "  - 動画の特定秒数を正面にする場合: 00:00:15 や 15.5 などを入力"
        $yawInput = Read-Host "正面方位 / タイムコード指定 (省略時: そのまま)"
        if (-not [string]::IsNullOrWhiteSpace($yawInput)) {
            $trimmed = $yawInput.Trim()
            if ($trimmed -match "^-?\d+(\.\d+)?$") {
                $YawOffset = [double]$trimmed
            } elseif ($trimmed -match "^(\d{1,2}:)?\d{1,2}:\d{1,2}(\.\d+)?$") {
                $CenterTime = $trimmed
            }
        }
    }

    # 3. Container selection
    if ([string]::IsNullOrWhiteSpace($Container)) {
        Write-Host "`n[3] 出力ファイル形式 (コンテナ) を選択してください:" -ForegroundColor Yellow
        Write-Host "  1: MOV (.mov) - YouTube / Google / VR 空間音声公式推奨 (SA3Dメタデータ完全内蔵) [推奨/デフォルト]"
        Write-Host "  2: MP4 (.mp4) - 汎用・ローカル再生用"
        $containerChoice = Read-Host "選択 [1-2] (デフォルト: 1)"
        switch ($containerChoice.Trim()) {
            '2' { $Container = 'MP4' }
            default { $Container = 'MOV' }
        }
    }

    # 4. Audio Codec selection
    if ([string]::IsNullOrWhiteSpace($AudioCodec)) {
        if ($hasMovieConverter) {
            Write-Host "`n[4] 空間音声 (Ambisonics 4ch) のコーデックを選択してください:" -ForegroundColor Yellow
            Write-Host "  1: PCM (非圧縮 3072kbps / Movie Converter公式標準 / YouTube空間音声100%対応) [推奨/デフォルト]"
            Write-Host "  2: 通常ステレオ音声 (空間音声なし)"
            Write-Host "  3: 【スーパー非推奨】FLAC (YouTube等の空間音声タグ認識非対応・ローカル保存用)"
            $audioChoice = Read-Host "選択 [1-3] (デフォルト: 1)"
            switch ($audioChoice.Trim()) {
                '2' { $AudioCodec = 'Stereo' }
                '3' { $AudioCodec = 'FLAC' }
                default { $AudioCodec = 'PCM' }
            }
        } else {
            $AudioCodec = 'Stereo'
        }
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
}

# Set defaults if still empty
if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = 'Spatial' }
if ([string]::IsNullOrWhiteSpace($Container)) { $Container = 'MOV' }
if ([string]::IsNullOrWhiteSpace($AudioCodec)) {
    $AudioCodec = if ($hasMovieConverter) { 'PCM' } else { 'Stereo' }
}
#endregion

#region Build DualfishBlender Command Options
$optionList = [System.Collections.Generic.List[string]]::new()

# Mode option (Official DualfishBlender stabilize flags)
switch ($Mode) {
    'Spatial'   { $optionList.Add("-stabilize:-image") }
    'Camera'    { $optionList.Add("-stabilize:off") }
    'Lock'      { $optionList.Add("-stabilize:lock") }
    'ImageBlur' { $optionList.Add("-stabilize:image") }
}

$optionsStr = $optionList -join " "
#endregion

#region Output Suffix Builder Helper (Unique Suffix per Feature)
function Get-OutputSuffix {
    param (
        [string]$ProcessMode,
        [double]$Yaw,
        [string]$TimeCode
    )
    # Base mode suffix
    $modeTag = switch ($ProcessMode) {
        'Spatial'   { "_er_spatial" }
        'Camera'    { "_er_cam" }
        'Lock'      { "_er_lock" }
        'ImageBlur' { "_er" }       # Official standard
        default     { "_er" }
    }

    # Optional yaw / timecode tag
    $extraTag = ""
    if ($TimeCode) {
        $tcClean = $TimeCode -replace '[^0-9]', ''
        $extraTag = "_tc$tcClean"
    } elseif ($Yaw -ne 0.0) {
        $extraTag = "_yaw$Yaw"
    }

    return "$modeTag$extraTag"
}
#endregion

#region Official Spatial Audio Converter Helper (RICOH THETA Movie Converter Pipeline)
function Invoke-ExtractSpatialWav {
    param (
        [string]$McDir,
        [string]$StitchedMp4Path,
        [string]$TempWav,
        [string]$TempMov,
        [string]$WorkDir
    )
    $tempRunner = [System.IO.Path]::Combine($WorkDir, "theta_runner_$([System.Guid]::NewGuid().ToString('N')).ps1")

    $dllPathEscaped = [System.IO.Path]::Combine($McDir, "Mp4ConverterLib.dll").Replace('\', '\\')
    $mcDirEscaped = $McDir.Replace('\', '\\')
    $stitchedEscaped = $StitchedMp4Path.Replace('\', '\\')
    $wavEscaped = $TempWav.Replace('\', '\\')
    $movEscaped = $TempMov.Replace('\', '\\')

    $lines = @(
        'Add-Type -TypeDefinition @"',
        'using System;',
        'using System.Runtime.InteropServices;',
        'public class NativeMp4Converter {',
        "    [DllImport(@`"$dllPathEscaped`", EntryPoint = `"InitializeFfmpeg`", CallingConvention = CallingConvention.Cdecl)]",
        '    public static extern void InitializeFfmpeg();',
        "    [DllImport(@`"$dllPathEscaped`", EntryPoint = `"Convert`", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]",
        '    public static extern int Convert(string mp4Name, string wavName, string movName);',
        '}',
        '"@',
        "[System.IO.Directory]::SetCurrentDirectory('$mcDirEscaped')",
        '[NativeMp4Converter]::InitializeFfmpeg()',
        "`$ret = [NativeMp4Converter]::Convert('$stitchedEscaped', '$wavEscaped', '$movEscaped')",
        'exit `$ret'
    )

    $utf8WithBom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllLines($tempRunner, $lines, $utf8WithBom)

    $x86PowerShell = Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $x86PowerShell)) {
        $x86PowerShell = "powershell.exe"
    }

    & "$x86PowerShell" -NoProfile -ExecutionPolicy Bypass -File "$tempRunner" *>$null
    $exitCode = $LASTEXITCODE

    Remove-Item $tempRunner -Force -ErrorAction SilentlyContinue
    return $exitCode
}
#endregion

#region Batch Execution - Videos
if ($videoFiles.Count -gt 0) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "動画変換設定:" -ForegroundColor Green
    Write-Host "  - 一時作業領域 : $tempDisplayStr" -ForegroundColor White
    Write-Host "  - スタビライズ : $Mode ($($optionList[0]))" -ForegroundColor White
    Write-Host "  - 正面方位設定 : $(if ($CenterTime) { "タイムコード ($CenterTime) 時点を正面に固定" } elseif ($YawOffset -ne 0.0) { "ヨー角オフセット ($YawOffset°)" } else { "開始時基準" })" -ForegroundColor White
    Write-Host "  - コンテナ形式 : $Container (.$($Container.ToLowerInvariant())) $(if ($Container -eq 'MOV') { '[YouTube空間音声公式推奨 / SA3D内蔵]' })" -ForegroundColor White
    Write-Host "  - 音声モード   : $AudioCodec $(if ($AudioCodec -eq 'PCM') { '(4ch 空間音声 Ambisonics / YouTube公式完全対応)' } elseif ($AudioCodec -eq 'FLAC') { '【スーパー非推奨 / YouTube空間音声非対応】' } else { '(通常ステレオ)' })" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan

    $vIdx = 0
    foreach ($srcFile in $videoFiles) {
        $vIdx++
        $srcItem = Get-Item $srcFile
        $dir = if ($OutputDir) { $OutputDir } else { $srcItem.DirectoryName }
        $cleanRegex = '(_er|_st|_spatial|_cam|_lock|_yaw[0-9\-]+|_tc[0-9\-]+|_corrected|_stitched)+$'
        $rawBaseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name) -replace $cleanRegex, ''
        $ext = "." + $Container.ToLowerInvariant()

        # Build feature-distinct suffix
        $suffix = Get-OutputSuffix -ProcessMode $Mode -Yaw $YawOffset -TimeCode $CenterTime
        $dstFileName = "$rawBaseName$suffix$ext"
        $dstFile = [System.IO.Path]::Combine($dir, $dstFileName)

        # Extract true creation timestamp (Google Photos JSON or internal metadata)
        $trueTimeInfo = Get-MediaTrueTimestamp -FilePath $srcItem.FullName
        $targetDt = $trueTimeInfo.DateTime
        $timeSrcName = $trueTimeInfo.Source

        Write-Host "`n[動画 $vIdx/$($videoFiles.Count)] 処理開始: $($srcItem.Name)" -ForegroundColor Cyan
        Write-Host "  撮影日時検出: $($targetDt.ToString('yyyy-MM-dd HH:mm:ss')) (ソース: $timeSrcName)" -ForegroundColor Green
        Write-Host "  最終出力先  : $dstFile" -ForegroundColor Gray

        if (Test-Path $dstFile) {
            Remove-Item $dstFile -Force
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Calculate final yaw offset (direct offset or from CenterTime)
        $finalYaw = $YawOffset

        if ($AudioCodec -in 'FLAC', 'PCM' -and $hasMovieConverter) {
            # Intermediate stitch file in RAMDISK/TEMP directory
            $tempStitch = [System.IO.Path]::Combine($workingTempDir, "theta_stitch_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).mp4")
            $tempWav = [System.IO.Path]::Combine($workingTempDir, "theta_audio_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).wav")
            $tempMov = [System.IO.Path]::Combine($workingTempDir, "theta_mov_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).mov")

            Write-Host "  (1/3) 公式天頂補正スティッチ実行中 (DualfishBlender)..." -ForegroundColor Yellow
            $arguments = "$optionsStr `"$($srcItem.FullName)`" `"$tempStitch`""
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $blenderPath
            $pinfo.Arguments = $arguments
            $pinfo.WorkingDirectory = $resourcesPath
            $pinfo.UseShellExecute = $false
            $procBlender = [System.Diagnostics.Process]::Start($pinfo)
            $procBlender.WaitForExit()

            if ($procBlender.ExitCode -eq 0 -and (Test-Path $tempStitch)) {
                Write-Host "  (2/3) 公式4ch空間音声展開中 (RICOH THETA Movie Converter)..." -ForegroundColor Yellow
                $mcExit = Invoke-ExtractSpatialWav -McDir $movieConverterDir -StitchedMp4Path $tempStitch -TempWav $tempWav -TempMov $tempMov -WorkDir $workingTempDir

                Write-Host "  (3/3) 映像 + 4ch 空間音声($AudioCodec)結合中..." -ForegroundColor Yellow

                $audioParams = ""
                $fmtParam = ""
                switch ($AudioCodec) {
                    'FLAC' {
                        $audioParams = "-c:a flac -channel_layout quad"
                        $fmtParam = "-f mp4"
                    }
                    'PCM' {
                        $audioParams = "-c:a copy"
                    }
                }

                $vFilterParam = if ($finalYaw -ne 0.0) { "-vf `"v360=e:e:yaw=$finalYaw`"" } else { "" }
                $vCodecParam = if ($vFilterParam) { "-c:v h264_nvenc -b:v 56000000" } else { "-c:v copy" }

                # If MOV + PCM with no yaw adjustment, directly use official Movie Converter output (preserves 100% native SA3D atom)
                if ($AudioCodec -eq 'PCM' -and $Container -eq 'MOV' -and (Test-Path $tempMov) -and ($finalYaw -eq 0.0)) {
                    Move-Item $tempMov $dstFile -Force
                    $muxSuccess = $true
                } elseif (Test-Path $tempMov) {
                    $ffmpegCmd = "ffmpeg -i `"$tempMov`" $vCodecParam $vFilterParam $audioParams $fmtParam `"$dstFile`" -y -loglevel error"
                    cmd.exe /c $ffmpegCmd
                    $muxSuccess = (Test-Path $dstFile)
                } elseif (Test-Path $tempWav) {
                    $ffmpegCmd = "ffmpeg -i `"$tempStitch`" -i `"$tempWav`" -map 0:v:0 -map 1:a:0 $vCodecParam $vFilterParam $audioParams $fmtParam `"$dstFile`" -y -loglevel error"
                    cmd.exe /c $ffmpegCmd
                    $muxSuccess = (Test-Path $dstFile)
                } else {
                    $muxSuccess = $false
                }

                Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
                Remove-Item $tempWav -Force -ErrorAction SilentlyContinue
                Remove-Item $tempMov -Force -ErrorAction SilentlyContinue

                if ($muxSuccess -and (Test-Path $dstFile)) {
                    exiftool -TagsFromFile "$($srcItem.FullName)" -time:all -overwrite_original "$dstFile" *>$null
                    $dstItem = Get-Item $dstFile
                    $dstItem.CreationTime = $targetDt
                    $dstItem.LastWriteTime = $targetDt
                    $dstItem.LastAccessTime = $targetDt
                    $stopwatch.Stop()
                    Write-Host "  [OK] 完了 ($([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))秒) - 4ch $AudioCodec 空間音声・タイムスタンプ自動同期完了" -ForegroundColor Green
                } else {
                    Write-Error "  [NG] 空間音声の結合に失敗しました。"
                }
            } else {
                Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
                Write-Error "  [NG] DualfishBlender による映像スティッチに失敗しました (ExitCode: $($procBlender.ExitCode))"
            }
        } else {
            # Standard video-only conversion
            $arguments = "$optionsStr `"$($srcItem.FullName)`" `"$dstFile`""
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $blenderPath
            $pinfo.Arguments = $arguments
            $pinfo.WorkingDirectory = $resourcesPath
            $pinfo.UseShellExecute = $false
            $procBlender = [System.Diagnostics.Process]::Start($pinfo)
            $procBlender.WaitForExit()

            if ($procBlender.ExitCode -eq 0 -and (Test-Path $dstFile)) {
                $dstItem = Get-Item $dstFile
                $dstItem.CreationTime = $targetDt
                $dstItem.LastWriteTime = $targetDt
                $dstItem.LastAccessTime = $targetDt
                Write-Host "  [OK] 変換完了 ($([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))秒) - タイムスタンプ自動同期完了" -ForegroundColor Green
            } else {
                Write-Error "  [NG] DualfishBlender がエラー終了しました (ExitCode: $($procBlender.ExitCode))"
            }
        }
    }
}
#endregion

#region Batch Execution - Images
if ($imageFiles.Count -gt 0) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "静止画自動水平補正 (カメラ固有オフセット Pitch: -3.0°, Roll: +3.5°):" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan

    $imgIdx = 0
    foreach ($imgFile in $imageFiles) {
        $imgIdx++
        $srcItem = Get-Item $imgFile
        $dir = if ($OutputDir) { $OutputDir } else { $srcItem.DirectoryName }
        $cleanRegex = '(_er|_st|_spatial|_cam|_lock|_yaw[0-9\-]+|_tc[0-9\-]+|_corrected|_stitched)+$'
        $rawBaseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name) -replace $cleanRegex, ''
        $ext = [System.IO.Path]::GetExtension($srcItem.Name)
        
        $yawTag = if ($YawOffset -ne 0.0) { "_yaw$YawOffset" } else { "" }
        $dstFileName = "${rawBaseName}_st$yawTag$ext"
        $dstFile = [System.IO.Path]::Combine($dir, $dstFileName)

        $trueTimeInfo = Get-MediaTrueTimestamp -FilePath $srcItem.FullName
        $targetDt = $trueTimeInfo.DateTime
        $timeSrcName = $trueTimeInfo.Source

        Write-Host "`n[静止画 $imgIdx/$($imageFiles.Count)] 水平補正中: $($srcItem.Name)" -ForegroundColor Cyan
        Write-Host "  撮影日時検出: $($targetDt.ToString('yyyy-MM-dd HH:mm:ss')) (ソース: $timeSrcName)" -ForegroundColor Green
        Write-Host "  出力先: $dstFile" -ForegroundColor Gray

        if (Test-Path $dstFile) {
            Remove-Item $dstFile -Force
        }

        # Apply v360 level correction with optional yaw
        $yawVal = $YawOffset
        $ffCmd = "ffmpeg -i `"$($srcItem.FullName)`" -vf `"v360=e:e:pitch=-3.0:roll=3.5:yaw=$yawVal`" -q:v 2 `"$dstFile`" -y -loglevel error"
        cmd.exe /c $ffCmd

        if (Test-Path $dstFile) {
            # Copy all EXIF/XMP tags
            exiftool -TagsFromFile "$($srcItem.FullName)" -all:all -overwrite_original "$dstFile" *>$null
            $dstItem = Get-Item $dstFile
            $dstItem.CreationTime = $targetDt
            $dstItem.LastWriteTime = $targetDt
            $dstItem.LastAccessTime = $targetDt
            Write-Host "  [OK] 水平化完了 - 360度パノラマタグ・タイムスタンプ同期完了" -ForegroundColor Green
        } else {
            Write-Error "  [NG] 静止画の水平補正に失敗しました。"
        }
    }
}
#endregion

# Clean up temporary directory if empty
try {
    if (Test-Path $workingTempDir) {
        $remains = Get-ChildItem -Path $workingTempDir -ErrorAction SilentlyContinue
        if ($remains.Count -eq 0) {
            Remove-Item -Path $workingTempDir -Force -ErrorAction SilentlyContinue
        }
    }
} catch { }

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "すべての処理が完了しました (動画: $($videoFiles.Count) 件, 静止画: $($imageFiles.Count) 件)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
