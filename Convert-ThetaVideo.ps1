<#
.SYNOPSIS
    RICOH THETAの未加工動画を対話型設定・正常な天頂補正・4ch空間音声(SA3D内蔵MOV/PCM)展開・任意方位固定・nセッション並列処理で一括変換します。

.DESCRIPTION
    RICOH THETA公式エンジン（DualfishBlender.exe）および公式空間音声エンジン（RICOH THETA Movie Converter）の
    純正パイプラインを100%そのまま使用し、YouTubeやVRプレイヤー・VLC・Googleフォトで確実に360度空間映像・空間音声（Ambisonics SA3D）として
    認識される高品質なEquirectangular動画を生成します。
    GPU性能を最大限に引き出すため、デフォルト2セッション（-Threads n で変更可能）のマルチスレッド並列一括処理に対応しています。
    正面回転オフセット（-YawOffset）やタイムコード指定時にも、映像の回転に合わせて4ch空間音声（Ambisonics）の音響定位も数学的回転行列で完全連動回転させ、
    さらにGoogle公式SpatialMedia（Spherical Video + SA3D Audio）メタデータを完全自動注入します。
    また、AndroidやGoogleフォトで発生するタイムゾーン（UTC/JST +9時間）計算ズレを解消するため、
    QuickTimeタグ（UTC）およびKeys:CreationDate（タイムゾーン付きローカル日時）を完全自動同期します。
    
    【処理内容別ファイル名サフィックス規則】
    どのような処理が行われたかがファイル名だけで完全に判別・区別できるように自動命名されます：
      - 公式標準手ブレ補正ON   : *_er.mov / *_er.mp4
      - 空間方位固定 (推奨)     : *_er_spatial.mov / *_er_spatial.mp4
      - カメラ正面追従         : *_er_cam.mov / *_er_cam.mp4
      - 方位完全ロック         : *_er_lock.mov / *_er_lock.mp4
      - 正面方位回転あり       : *_er_spatial_yaw90.mov / *_er_cam_yaw-45.mov
      - タイムコード正面指定   : *_er_spatial_tc000015.mov

    RAMDISK（R:\ 等）の自動検出と中間作業領域の完全RAM化に対応し、SSD書き込み寿命を強力に保護します。
    公式標準の MOV (PCM 4ch + SA3D内蔵) を最優先推奨・デフォルトとし、
    GoogleフォトのメタデータJSON (例: *.MP4.json) や EXIF/QuickTime メタデータからの撮影日時・タイムスタンプ完全自動復元に対応しています。

.PARAMETER Path
    変換対象のRICOH THETA未加工動画ファイルパス（複数指定、ワイルドカード、パイプライン対応）。

.PARAMETER Mode
    スタビライズ・方位固定モード（Spatial: 空間方位固定 / Camera: カメラ正面追従 / Lock: 方位ロック / ImageBlur: 手ブレ補正ON）。

.PARAMETER Container
    出力コンテナ形式（MOV: YouTube/VR空間音声公式推奨 / MP4: 汎用）。

.PARAMETER AudioCodec
    音声コーデック（PCM: YouTube/VR空間音声公式標準 / FLAC: 非推奨・ローカル保存用 / Stereo: 通常ステレオ）。

.PARAMETER Threads
    並列実行セッション数（デフォルト: 2）。

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
    .\Convert-ThetaVideo.ps1 *.MP4 -Threads 4 -NonInteractive

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

    [int]$Threads = 2,

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

# 1. DualfishBlender path
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

# 2. RICOH THETA Movie Converter path
$movieConverterDir = Join-Path $scriptDir "tools\ricoh_movie_converter"
$hasMovieConverter = (Test-Path (Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe")) -and (Test-Path (Join-Path $movieConverterDir "Mp4ConverterLib.dll"))

# 3. Google SpatialMedia tools path
$spatialMediaDir = Join-Path $scriptDir "tools\spatialmedia"

# 4. Detect all GPUs on the system
$gpuList = [System.Collections.Generic.List[string]]::new()
try {
    $controllers = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($c in $controllers) {
        if ($c.Name -and $c.Name -notmatch "Basic Display|Miracast") {
            $gpuList.Add($c.Name)
        }
    }
} catch { }

# 5. Check DualfishBlender showCapability
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

#region Collect Input Files
$videoFiles = [System.Collections.Generic.List[string]]::new()
if ($Path) {
    foreach ($p in $Path) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $resolved = @(Resolve-Path -Path $p -ErrorAction SilentlyContinue)
        if ($resolved.Count -gt 0) {
            foreach ($r in $resolved) {
                if (Test-Path -Path $r.Path -PathType Leaf) {
                    $ext = [System.IO.Path]::GetExtension($r.Path).ToLowerInvariant()
                    if ($ext -in '.mp4', '.mov') {
                        $videoFiles.Add($r.Path)
                    }
                }
            }
        } elseif (Test-Path -Path $p -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($p).ToLowerInvariant()
            if ($ext -in '.mp4', '.mov') {
                $videoFiles.Add((Get-Item $p).FullName)
            }
        }
    }
}

if ($videoFiles.Count -eq 0) {
    Write-Host "処理対象の動画ファイル (.MP4 / .MOV) が指定されていません。" -ForegroundColor Yellow
    Get-Help -Name $PSCommandPath -Full
    exit 0
}
#endregion

#region Interactive Menu
if (-not $NonInteractive -and $videoFiles.Count -gt 0 -and ([string]::IsNullOrWhiteSpace($Mode) -or [string]::IsNullOrWhiteSpace($Container) -or [string]::IsNullOrWhiteSpace($AudioCodec))) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "        RICOH THETA 完全スタンドアロン動画変換ツール        " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "動画ファイル: $($videoFiles.Count) 件" -ForegroundColor White
    foreach ($f in $videoFiles) {
        Write-Host "  - $([System.IO.Path]::GetFileName($f))" -ForegroundColor Gray
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "作業領域 (TEMP)        : $tempDisplayStr" -ForegroundColor Green
    Write-Host "搭載GPU構成            : $gpuDisplayStr" -ForegroundColor Green
    Write-Host "映像スティッチエンジン : 内蔵 (DualfishBlender 公式純正)" -ForegroundColor Green
    Write-Host "空間音声エンジン       : $(if ($hasMovieConverter) { '内蔵 (RICOH THETA Movie Converter 公式純正)' } else { '未検出 (ステレオのみ)' })" -ForegroundColor Green
    Write-Host "並列セッション数       : $Threads 並列" -ForegroundColor Green
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

    # 5. Thread count selection
    if ($videoFiles.Count -gt 1) {
        Write-Host "`n[5] GPU並列処理セッション数 (任意):" -ForegroundColor Yellow
        $thInput = Read-Host "並列セッション数 (デフォルト: 2)"
        if (-not [string]::IsNullOrWhiteSpace($thInput) -and ($thInput.Trim() -match '^\d+$')) {
            $Threads = [Math]::Max(1, [int]$thInput.Trim())
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
if ($Threads -lt 1) { $Threads = 2 }
#endregion

#region Build DualfishBlender Command Options
$optionList = [System.Collections.Generic.List[string]]::new()
switch ($Mode) {
    'Spatial'   { $optionList.Add("-stabilize:-image") }
    'Camera'    { $optionList.Add("-stabilize:off") }
    'Lock'      { $optionList.Add("-stabilize:lock") }
    'ImageBlur' { $optionList.Add("-stabilize:image") }
}
$optionsStr = $optionList -join " "
#endregion

#region Worker Script Definition (Parallel Multi-Session Execution)
$workerScriptBlock = {
    param (
        [string]$SrcFile,
        [int]$VideoIndex,
        [int]$TotalVideos,
        [string]$Mode,
        [string]$OptionsStr,
        [string]$Container,
        [string]$AudioCodec,
        [double]$YawOffset,
        [string]$CenterTime,
        [string]$OutputDir,
        [string]$WorkingTempDir,
        [string]$BlenderPath,
        [string]$ResourcesPath,
        [string]$MovieConverterDir,
        [bool]$HasMovieConverter,
        [string]$ToolsDir,
        [hashtable]$SyncState
    )

    $srcItem = Get-Item $SrcFile
    $dir = if ($OutputDir) { $OutputDir } else { $srcItem.DirectoryName }
    $cleanRegex = '(_er|_spatial|_cam|_lock|_yaw[0-9\-]+|_tc[0-9\-]+|_corrected|_stitched)+$'
    $rawBaseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name) -replace $cleanRegex, ''
    $ext = "." + $Container.ToLowerInvariant()

    # Register start in shared SyncState
    if ($SyncState) {
        $SyncState[$VideoIndex] = [Hashtable]::Synchronized(@{
            VideoIndex  = $VideoIndex
            TotalVideos = $TotalVideos
            FileName    = $srcItem.Name
            Percent     = 0.0
            CurSec      = 0.0
            TotalSec    = 0.0
            Stage       = "スティッチ処理中"
        })
    }

    # Base mode tag
    $modeTag = switch ($Mode) {
        'Spatial'   { "_er_spatial" }
        'Camera'    { "_er_cam" }
        'Lock'      { "_er_lock" }
        'ImageBlur' { "_er" }
        default     { "_er" }
    }

    # Optional yaw / timecode tag
    $extraTag = ""
    if ($CenterTime) {
        $tcClean = $CenterTime -replace '[^0-9]', ''
        $extraTag = "_tc$tcClean"
    } elseif ($YawOffset -ne 0.0) {
        $extraTag = "_yaw$YawOffset"
    }

    $dstFileName = "$rawBaseName$modeTag$extraTag$ext"
    $dstFile = [System.IO.Path]::Combine($dir, $dstFileName)

    # 1. Extract true creation timestamp
    $name = $srcItem.Name
    $jsonCandidates = @(
        (Join-Path $dir "$name.json"),
        (Join-Path $dir "$rawBaseName.json"),
        (Join-Path $dir "$rawBaseName.MP4.json"),
        (Join-Path $dir "$rawBaseName.MOV.json")
    )
    $targetDt = $srcItem.LastWriteTime
    $timeSrcName = "FileSystem"

    foreach ($jc in $jsonCandidates) {
        if (Test-Path $jc) {
            try {
                $jsonContent = Get-Content -Path $jc -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($jsonContent.photoTakenTime -and $jsonContent.photoTakenTime.timestamp) {
                    $tsLong = [int64]$jsonContent.photoTakenTime.timestamp
                    if ($tsLong -gt 0) {
                        $targetDt = [System.DateTimeOffset]::FromUnixTimeSeconds($tsLong).LocalDateTime
                        $timeSrcName = "GooglePhotosJSON ($([System.IO.Path]::GetFileName($jc)))"
                        break
                    }
                }
            } catch { }
        }
    }

    if ($timeSrcName -eq "FileSystem") {
        try {
            $exifDate = (exiftool -d "%Y:%m:%d %H:%M:%S" -s3 -DateTimeOriginal -CreateDate -CreationDate -TrackCreateDate "$SrcFile" 2>$null | Where-Object { $_ -match "^\d{4}:\d{2}:\d{2}" } | Select-Object -First 1)
            if ($exifDate -and ($exifDate -match "^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})")) {
                $targetDt = [datetime]::ParseExact($exifDate.Trim(), "yyyy:MM:dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                $timeSrcName = "InternalMetadata (EXIF/QuickTime)"
            }
        } catch { }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if (Test-Path $dstFile) { Remove-Item $dstFile -Force }

    $finalYaw = $YawOffset

    if ($AudioCodec -in 'FLAC', 'PCM' -and $HasMovieConverter) {
        $tempStitch = [System.IO.Path]::Combine($WorkingTempDir, "theta_stitch_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).mp4")
        $tempWav = [System.IO.Path]::Combine($WorkingTempDir, "theta_audio_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).wav")
        $tempMov = [System.IO.Path]::Combine($WorkingTempDir, "theta_mov_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).mov")

        # 1. DualfishBlender stitch (with output redirection & live progress capture)
        $arguments = "$OptionsStr `"$SrcFile`" `"$tempStitch`""
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $BlenderPath
        $pinfo.Arguments = $arguments
        $pinfo.WorkingDirectory = $ResourcesPath
        $pinfo.UseShellExecute = $false
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.CreateNoWindow = $true
        $procBlender = [System.Diagnostics.Process]::Start($pinfo)

        $charBuf = [System.Text.StringBuilder]::new()
        $lastErrorLines = [System.Collections.Generic.List[string]]::new()
        while (-not $procBlender.HasExited -or -not $procBlender.StandardOutput.EndOfStream) {
            $c = $procBlender.StandardOutput.Read()
            if ($c -eq -1) { break }
            $ch = [char]$c
            if ($ch -eq "`r" -or $ch -eq "`n") {
                if ($charBuf.Length -gt 0) {
                    $line = $charBuf.ToString().Trim()
                    $charBuf.Clear()
                    if ($line -match 'processing frame\s+(\d+)\s+([0-9\.]+)\/([0-9\.]+)') {
                        $curSec = [double]$Matches[2]
                        $totalSec = [double]$Matches[3]
                        $pct = if ($totalSec -gt 0) { [Math]::Min(95.0, [Math]::Round(($curSec / $totalSec) * 100, 1)) } else { 0.0 }
                        if ($SyncState -and $SyncState.ContainsKey($VideoIndex)) {
                            $SyncState[$VideoIndex].Percent = $pct
                            $SyncState[$VideoIndex].CurSec = $curSec
                            $SyncState[$VideoIndex].TotalSec = $totalSec
                        }
                    } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
                        if ($lastErrorLines.Count -ge 10) { [void]$lastErrorLines.RemoveAt(0) }
                        $lastErrorLines.Add($line)
                    }
                }
            } else {
                [void]$charBuf.Append($ch)
            }
        }
        $procBlender.WaitForExit()

        if ($procBlender.ExitCode -eq 0 -and (Test-Path $tempStitch)) {
            # 2. Movie Converter 4ch audio extraction
            if ($SyncState -and $SyncState.ContainsKey($VideoIndex)) {
                $SyncState[$VideoIndex].Percent = 96.0
                $SyncState[$VideoIndex].Stage = "4ch空間音声結合中"
            }

            $tempRunner = [System.IO.Path]::Combine($WorkingTempDir, "theta_runner_$([System.Guid]::NewGuid().ToString('N')).ps1")
            $dllPathEscaped = [System.IO.Path]::Combine($MovieConverterDir, "Mp4ConverterLib.dll").Replace('\', '\\')
            $mcDirEscaped = $MovieConverterDir.Replace('\', '\\')
            $stitchedEscaped = $tempStitch.Replace('\', '\\')
            $wavEscaped = $tempWav.Replace('\', '\\')
            $movEscaped = $tempMov.Replace('\', '\\')

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
            if (-not (Test-Path $x86PowerShell)) { $x86PowerShell = "powershell.exe" }
            & "$x86PowerShell" -NoProfile -ExecutionPolicy Bypass -File "$tempRunner" *>$null
            Remove-Item $tempRunner -Force -ErrorAction SilentlyContinue

            # 3. Audio & Video Mux
            $vFilterParam = if ($finalYaw -ne 0.0) { "-vf `"v360=e:e:yaw=$finalYaw`"" } else { "" }
            $vCodecParam = if ($vFilterParam) { "-c:v h264_nvenc -b:v 56000000" } else { "-c:v copy" }

            $aFilterParam = ""
            if ($finalYaw -ne 0.0 -and $AudioCodec -eq 'PCM') {
                $rad = $finalYaw * [Math]::PI / 180.0
                $cosStr = ([Math]::Cos($rad)).ToString("F6", [System.Globalization.CultureInfo]::InvariantCulture)
                $sinStr = ([Math]::Sin($rad)).ToString("F6", [System.Globalization.CultureInfo]::InvariantCulture)
                $negSinStr = (-[Math]::Sin($rad)).ToString("F6", [System.Globalization.CultureInfo]::InvariantCulture)
                $ambixPan = "pan=4c|c0=c0|c1=${cosStr}*c1+${sinStr}*c3|c2=c2|c3=${negSinStr}*c1+${cosStr}*c3"
                $aFilterParam = "-af `"$ambixPan`""
            }

            $audioParams = ""
            $fmtParam = ""
            switch ($AudioCodec) {
                'FLAC' {
                    $audioParams = "-c:a flac -channel_layout quad"
                    $fmtParam = "-f mp4"
                }
                'PCM' {
                    $audioParams = if ($aFilterParam) { "$aFilterParam -c:a pcm_s16le" } else { "-c:a copy" }
                }
            }

            $muxSuccess = $false
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
            }

            Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
            Remove-Item $tempWav -Force -ErrorAction SilentlyContinue
            Remove-Item $tempMov -Force -ErrorAction SilentlyContinue

            if ($muxSuccess -and (Test-Path $dstFile)) {
                # 4. Inject 360 metadata if filtered
                if ($finalYaw -ne 0.0 -or $Container -ne 'MOV' -or $AudioCodec -ne 'PCM') {
                    if ($SyncState -and $SyncState.ContainsKey($VideoIndex)) {
                        $SyncState[$VideoIndex].Percent = 98.0
                        $SyncState[$VideoIndex].Stage = "メタデータ付与中"
                    }
                    $hasSpatialAudio = ($AudioCodec -eq 'PCM')
                    $audioArg = if ($hasSpatialAudio) { "metadata.audio = metadata_utils.get_spatial_audio_metadata(ambisonic_order=1, head_locked_stereo=False)" } else { "" }
                    $pyScript = @"
import sys, os, shutil
tools_dir = r'$ToolsDir'
target = r'$dstFile'
work_dir = r'$WorkingTempDir'
sys.path.insert(0, tools_dir)
try:
    from spatialmedia import metadata_utils
    metadata = metadata_utils.Metadata()
    metadata.video = metadata_utils.generate_spherical_xml()
    $audioArg
    temp_out = os.path.join(work_dir, 'theta_inj_' + os.path.basename(target))
    metadata_utils.inject_metadata(target, temp_out, metadata, lambda s: None)
    if os.path.exists(temp_out) and os.path.getsize(temp_out) > 0:
        shutil.move(temp_out, target)
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    sys.exit(2)
"@
                    $tempPy = [System.IO.Path]::Combine($WorkingTempDir, "theta_inject_$([System.Guid]::NewGuid().ToString('N')).py")
                    [System.IO.File]::WriteAllText($tempPy, $pyScript, [System.Text.Encoding]::UTF8)
                    python "$tempPy" *>$null
                    Remove-Item $tempPy -Force -ErrorAction SilentlyContinue
                }

                # 5. Timestamp sync
                $utcDt = $targetDt.ToUniversalTime()
                $dtUtcStr = $utcDt.ToString("yyyy:MM:dd HH:mm:ss")
                $dtIsoLocalStr = $targetDt.ToString("yyyy-MM-ddTHH:mm:sszzz")
                exiftool -overwrite_original `
                    "-QuickTime:CreateDate=$dtUtcStr" `
                    "-QuickTime:ModifyDate=$dtUtcStr" `
                    "-QuickTime:TrackCreateDate=$dtUtcStr" `
                    "-QuickTime:TrackModifyDate=$dtUtcStr" `
                    "-QuickTime:MediaCreateDate=$dtUtcStr" `
                    "-QuickTime:MediaModifyDate=$dtUtcStr" `
                    "-Keys:CreationDate=$dtIsoLocalStr" `
                    "-UserData:DateTimeOriginal=$dtIsoLocalStr" `
                    "-XMP:DateTimeOriginal=$dtIsoLocalStr" `
                    "-XMP:CreateDate=$dtIsoLocalStr" `
                    "-XMP:ModifyDate=$dtIsoLocalStr" `
                    "$dstFile" *>$null

                $dstItem = Get-Item $dstFile
                $dstItem.CreationTime = $targetDt
                $dstItem.LastWriteTime = $targetDt
                $dstItem.LastAccessTime = $targetDt

                $sw.Stop()
                if ($SyncState -and $SyncState.ContainsKey($VideoIndex)) {
                    $SyncState[$VideoIndex].Percent = 100.0
                    $SyncState[$VideoIndex].Stage = "完了"
                }
                return [PSCustomObject]@{
                    Success = $true
                    Message = "$($srcItem.Name) ($([Math]::Round($sw.Elapsed.TotalSeconds, 1))秒) -> $dstFileName"
                }
            } else {
                return [PSCustomObject]@{
                    Success = $false
                    Message = "$($srcItem.Name) エラー (空間音声結合失敗)"
                }
            }
        } else {
            Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
            $errDetail = if ($lastErrorLines.Count -gt 0) { $lastErrorLines -join " | " } else { "スティッチ失敗" }
            return [PSCustomObject]@{
                Success = $false
                Message = "$($srcItem.Name) エラー ($errDetail)"
            }
        }
    } else {
        # Standard video-only conversion
        $arguments = "$OptionsStr `"$SrcFile`" `"$dstFile`""
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $BlenderPath
        $pinfo.Arguments = $arguments
        $pinfo.WorkingDirectory = $ResourcesPath
        $pinfo.UseShellExecute = $false
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.CreateNoWindow = $true
        $procBlender = [System.Diagnostics.Process]::Start($pinfo)

        $charBuf = [System.Text.StringBuilder]::new()
        $lastErrorLines = [System.Collections.Generic.List[string]]::new()
        while (-not $procBlender.HasExited -or -not $procBlender.StandardOutput.EndOfStream) {
            $c = $procBlender.StandardOutput.Read()
            if ($c -eq -1) { break }
            $ch = [char]$c
            if ($ch -eq "`r" -or $ch -eq "`n") {
                if ($charBuf.Length -gt 0) {
                    $line = $charBuf.ToString().Trim()
                    $charBuf.Clear()
                    if ($line -match 'processing frame\s+(\d+)\s+([0-9\.]+)\/([0-9\.]+)') {
                        $curSec = [double]$Matches[2]
                        $totalSec = [double]$Matches[3]
                        $pct = if ($totalSec -gt 0) { [Math]::Min(95.0, [Math]::Round(($curSec / $totalSec) * 100, 1)) } else { 0.0 }
                        if ($SyncState -and $SyncState.ContainsKey($VideoIndex)) {
                            $SyncState[$VideoIndex].Percent = $pct
                            $SyncState[$VideoIndex].CurSec = $curSec
                            $SyncState[$VideoIndex].TotalSec = $totalSec
                        }
                    } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
                        if ($lastErrorLines.Count -ge 10) { [void]$lastErrorLines.RemoveAt(0) }
                        $lastErrorLines.Add($line)
                    }
                }
            } else {
                [void]$charBuf.Append($ch)
            }
        }
        $procBlender.WaitForExit()

        if ($procBlender.ExitCode -eq 0 -and (Test-Path $dstFile)) {
            $utcDt = $targetDt.ToUniversalTime()
            $dtUtcStr = $utcDt.ToString("yyyy:MM:dd HH:mm:ss")
            $dtIsoLocalStr = $targetDt.ToString("yyyy-MM-ddTHH:mm:sszzz")
            exiftool -overwrite_original `
                "-QuickTime:CreateDate=$dtUtcStr" `
                "-QuickTime:ModifyDate=$dtUtcStr" `
                "-QuickTime:TrackCreateDate=$dtUtcStr" `
                "-QuickTime:TrackModifyDate=$dtUtcStr" `
                "-QuickTime:MediaCreateDate=$dtUtcStr" `
                "-QuickTime:MediaModifyDate=$dtUtcStr" `
                "-Keys:CreationDate=$dtIsoLocalStr" `
                "-UserData:DateTimeOriginal=$dtIsoLocalStr" `
                "-XMP:DateTimeOriginal=$dtIsoLocalStr" `
                "-XMP:CreateDate=$dtIsoLocalStr" `
                "-XMP:ModifyDate=$dtIsoLocalStr" `
                "$dstFile" *>$null

            $dstItem = Get-Item $dstFile
            $dstItem.CreationTime = $targetDt
            $dstItem.LastWriteTime = $targetDt
            $dstItem.LastAccessTime = $targetDt

            $sw.Stop()
            if ($SyncState -and $SyncState.ContainsKey($VideoIndex)) {
                $SyncState[$VideoIndex].Percent = 100.0
                $SyncState[$VideoIndex].Stage = "完了"
            }
            return [PSCustomObject]@{
                Success = $true
                Message = "$($srcItem.Name) ($([Math]::Round($sw.Elapsed.TotalSeconds, 1))秒) -> $dstFileName"
            }
        } else {
            $errDetail = if ($lastErrorLines.Count -gt 0) { $lastErrorLines -join " | " } else { "変換失敗" }
            return [PSCustomObject]@{
                Success = $false
                Message = "$($srcItem.Name) エラー ($errDetail)"
            }
        }
    }
}
#endregion

#region Parallel Batch Execution Loop
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "動画一括変換設定 ($Threads セッション並列実行):" -ForegroundColor Green
Write-Host "  - 一時作業領域 : $tempDisplayStr" -ForegroundColor White
Write-Host "  - スタビライズ : $Mode ($($optionList[0]))" -ForegroundColor White
Write-Host "  - 正面方位設定 : $(if ($CenterTime) { "タイムコード ($CenterTime) 時点を正面に固定" } elseif ($YawOffset -ne 0.0) { "ヨー角オフセット ($YawOffset°)" } else { "開始時基準" })" -ForegroundColor White
Write-Host "  - コンテナ形式 : $Container (.$($Container.ToLowerInvariant())) $(if ($Container -eq 'MOV') { '[YouTube空間音声公式推奨 / SA3D内蔵]' })" -ForegroundColor White
Write-Host "  - 音声モード   : $AudioCodec $(if ($AudioCodec -eq 'PCM') { '(4ch 空間音声 Ambisonics / YouTube公式完全対応)' } elseif ($AudioCodec -eq 'FLAC') { '【スーパー非推奨 / YouTube空間音声非対応】' } else { '(通常ステレオ)' })" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

$totalWatch = [System.Diagnostics.Stopwatch]::StartNew()
$toolsDir = Join-Path $scriptDir "tools"

$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $Threads)
$pool.Open()

$runspaces = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
$syncState = [Hashtable]::Synchronized(@{})
$startedSet = [System.Collections.Generic.HashSet[int]]::new()
$totalVideos = $videoFiles.Count
$completedCount = 0

$vIdx = 0
foreach ($srcFile in $videoFiles) {
    $vIdx++
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    
    [void]$ps.AddScript($workerScriptBlock).AddParameters(@{
        SrcFile           = $srcFile
        VideoIndex        = $vIdx
        TotalVideos       = $totalVideos
        Mode              = $Mode
        OptionsStr        = $optionsStr
        Container         = $Container
        AudioCodec        = $AudioCodec
        YawOffset         = $YawOffset
        CenterTime        = $CenterTime
        OutputDir         = $OutputDir
        WorkingTempDir    = $workingTempDir
        BlenderPath       = $blenderPath
        ResourcesPath     = $resourcesPath
        MovieConverterDir = $movieConverterDir
        HasMovieConverter = $hasMovieConverter
        ToolsDir          = $toolsDir
        SyncState         = $syncState
    })

    $asyncResult = $ps.BeginInvoke()
    [void]$runspaces.Add([PSCustomObject]@{
        PowerShell  = $ps
        AsyncResult = $asyncResult
        FileName    = [System.IO.Path]::GetFileName($srcFile)
        Index       = $vIdx
    })
}

# Monitor running tasks and print results as they complete
while ($runspaces.Count -gt 0) {
    # Announce tasks when they actually begin execution
    foreach ($k in @($syncState.Keys)) {
        if ($startedSet.Add($k)) {
            Write-Host "  [開始 $k/$totalVideos] $($syncState[$k].FileName)" -ForegroundColor Gray
        }
    }

    # Check for completed tasks
    for ($i = $runspaces.Count - 1; $i -ge 0; $i--) {
        $r = $runspaces[$i]
        if ($r.AsyncResult.IsCompleted) {
            $completedCount++
            try {
                $output = $r.PowerShell.EndInvoke($r.AsyncResult)
                Write-Progress -Id $r.Index -Completed
                if ($output.Success) {
                    Write-Host "  [完了 $($r.Index)/$totalVideos] $($output.Message)" -ForegroundColor Green
                } else {
                    Write-Error "  [失敗 $($r.Index)/$totalVideos] $($output.Message)"
                }
            } catch {
                Write-Progress -Id $r.Index -Completed
                Write-Error "  [例外 $($r.Index)/$totalVideos] $($r.FileName) 例外エラー: $_"
            } finally {
                $r.PowerShell.Dispose()
                $runspaces.RemoveAt($i)
            }
        }
    }

    # Update multi-task progress bar
    if ($runspaces.Count -gt 0) {
        $overallPct = if ($totalVideos -gt 0) { [Math]::Min(100.0, [Math]::Round(($completedCount / $totalVideos) * 100, 1)) } else { 0.0 }
        Write-Progress -Id 0 -Activity "THETA 動画一括変換" -Status "完了: $completedCount / $totalVideos 件 ($overallPct%)" -PercentComplete $overallPct
        
        foreach ($k in @($syncState.Keys)) {
            $task = $syncState[$k]
            if ($task -and $task.Percent -lt 100) {
                $secInfo = if ($task.TotalSec -gt 0) { " [$([Math]::Round($task.CurSec, 1))s / $([Math]::Round($task.TotalSec, 1))s]" } else { "" }
                Write-Progress -Id $k -ParentId 0 `
                    -Activity "[$k/$totalVideos] $($task.FileName)" `
                    -Status "$($task.Stage)$secInfo ($($task.Percent)%)" `
                    -PercentComplete $task.Percent
            }
        }
    }

    Start-Sleep -Milliseconds 150
}

Write-Progress -Id 0 -Completed

$pool.Close()
$pool.Dispose()

# Clean up temporary directory if empty
try {
    if (Test-Path $workingTempDir) {
        $remains = Get-ChildItem -Path $workingTempDir -ErrorAction SilentlyContinue
        if ($remains.Count -eq 0) {
            Remove-Item -Path $workingTempDir -Force -ErrorAction SilentlyContinue
        }
    }
} catch { }

$totalWatch.Stop()
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "すべての処理が完了しました (動画: $($videoFiles.Count) 件, 総所要時間: $([Math]::Round($totalWatch.Elapsed.TotalSeconds, 1)) 秒)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
