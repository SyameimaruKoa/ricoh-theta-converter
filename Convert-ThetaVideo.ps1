<#
.SYNOPSIS
    RICOH THETAの動画・静止画を対話型設定・正常な天頂補正・4ch空間音声(FLAC)展開で一括変換します。

.DESCRIPTION
    RICOH THETA公式エンジン（DualfishBlender.exe）および RICOH THETA Movie Converter を内蔵し、
    手ブレ補正による映像の傾き不具合を解消した高品質な360度Equirectangular動画を生成します。
    4ch 空間音声（First-Order Ambisonics AmbiX + SA3D）の FLAC(可逆圧縮)/PCM(非圧縮)展開、
    MP4 / MOV コンテナ選択、空間方位固定/カメラ正面追従/方位ロックの切り替え、H.265コーデック、GPUエンコーダー選択、
    SSD書き込みを最小限に抑える中間ファイル自動整理、および
    ファイル作成日・更新日・EXIF撮影日メタデータの完全引き継ぎ（Googleフォト対応）に対応しています。
    また、静止画（.JPG）が渡された場合はカメラの姿勢オフセットを自動解消して水平化します。

.PARAMETER Path
    変換対象のRICOH THETA動画・静止画ファイルパス（複数指定、ワイルドカード、パイプライン対応）。

.PARAMETER Mode
    スタビライズ・方位固定モード（Spatial: 空間方位固定 / Camera: カメラ正面追従 / Lock: 方位ロック）。

.PARAMETER Codec
    出力動画コーデック（H264 / H265）。

.PARAMETER Encoder
    エンコーダー指定（Auto / NVENC / QSV / CPU / AMF）。

.PARAMETER Container
    出力コンテナ形式（MP4 / MOV）。

.PARAMETER AudioCodec
    音声コーデック（FLAC: 可逆圧縮軽量化 / PCM: 非圧縮 / Stereo: 通常ステレオ）。

.PARAMETER OutputDir
    出力先ディレクトリ（省略時は元ファイルと同じフォルダ）。

.PARAMETER NonInteractive
    対話プロンプトを表示せず、指定されたパラメータ（またはデフォルト値）で即時実行します。

.PARAMETER Help
    ヘルプ情報を表示します（-h または --help）。

.EXAMPLE
    .\Convert-ThetaVideo.ps1 -Path .\R0010414.MP4

.EXAMPLE
    .\Convert-ThetaVideo.ps1 *.MP4 -Mode Spatial -Codec H265 -Container MP4 -AudioCodec FLAC -NonInteractive

.EXAMPLE
    Get-ChildItem *.MP4 | .\Convert-ThetaVideo.ps1

.EXAMPLE
    .\Convert-ThetaVideo.ps1 -h
#>
[CmdletBinding(DefaultParameterSetName = 'Convert')]
param (
    #region Parameters
    [Parameter(ParameterSetName = 'Help')]
    [Alias('h', '-help')]
    [switch]$Help,

    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Convert')]
    [string[]]$Path,

    [Parameter(ParameterSetName = 'Convert')]
    [ValidateSet('Spatial', 'Camera', 'Lock')]
    [string]$Mode,

    [Parameter(ParameterSetName = 'Convert')]
    [ValidateSet('H264', 'H265')]
    [string]$Codec,

    [Parameter(ParameterSetName = 'Convert')]
    [ValidateSet('Auto', 'NVENC', 'QSV', 'CPU', 'AMF')]
    [string]$Encoder,

    [Parameter(ParameterSetName = 'Convert')]
    [ValidateSet('MP4', 'MOV')]
    [string]$Container,

    [Parameter(ParameterSetName = 'Convert')]
    [ValidateSet('FLAC', 'PCM', 'Stereo')]
    [string]$AudioCodec,

    [Parameter(ParameterSetName = 'Convert')]
    [string]$OutputDir,

    [Parameter(ParameterSetName = 'Convert')]
    [switch]$NonInteractive
    #endregion
)

#region Help Handling
if ($Help -or ($PSCmdlet.ParameterSetName -eq 'Help') -or (($PSCmdlet.ParameterSetName -eq 'Convert') -and (-not $Path) -and (-not $NonInteractive))) {
    if (-not $Path -and -not $Help) {
        Get-Help -Name $PSCommandPath -Full
        exit 0
    }
}
if ($Help) {
    Get-Help -Name $PSCommandPath -Full
    exit 0
}
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

# 2. RICOH THETA Movie Converter path
$movieConverterDir = Join-Path $scriptDir "tools\ricoh_movie_converter"
$hasMovieConverter = (Test-Path (Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe")) -and (Test-Path (Join-Path $movieConverterDir "Mp4ConverterLib.dll"))

# 3. Run showCapability to check GPU environment
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
if (-not $NonInteractive -and $videoFiles.Count -gt 0 -and ([string]::IsNullOrWhiteSpace($Mode) -or [string]::IsNullOrWhiteSpace($Codec) -or [string]::IsNullOrWhiteSpace($Encoder) -or [string]::IsNullOrWhiteSpace($Container) -or [string]::IsNullOrWhiteSpace($AudioCodec))) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "        RICOH THETA 完全スタンドアロン一括変換ツール        " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "動画ファイル: $($videoFiles.Count) 件, 静止画ファイル: $($imageFiles.Count) 件" -ForegroundColor White
    foreach ($f in $inputFiles) {
        Write-Host "  - $([System.IO.Path]::GetFileName($f))" -ForegroundColor Gray
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "映像スティッチエンジン : 内蔵 (DualfishBlender)" -ForegroundColor Green
    Write-Host "空間音声エンジン       : $(if ($hasMovieConverter) { '内蔵 (Ambisonics AmbiX + SA3D)' } else { '未検出 (ステレオのみ)' })" -ForegroundColor Green
    Write-Host "検出されたGPU環境      : $detectedGpu" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    # 1. Mode selection
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        Write-Host "`n[1] スタビライズ / 方位固定モードを選択してください:" -ForegroundColor Yellow
        Write-Host "  1: 空間方位固定 (ジャイロ天頂補正 + 空間方位固定, 画像認識OFF) [-stabilize:-image] [推奨/デフォルト]"
        Write-Host "  2: カメラ正面追従 (ジャイロ天頂補正 + カメラレンズ正面追従) [-stabilize:off]"
        Write-Host "  3: 方位完全ロック (ジャイロ天頂補正 + 撮影開始時の方位完全ロック) [-stabilize:lock]"
        $modeChoice = Read-Host "選択 [1-3] (デフォルト: 1)"
        switch ($modeChoice.Trim()) {
            '2' { $Mode = 'Camera' }
            '3' { $Mode = 'Lock' }
            default { $Mode = 'Spatial' }
        }
    }

    # 2. Codec selection
    if ([string]::IsNullOrWhiteSpace($Codec)) {
        Write-Host "`n[2] 出力動画コーデックを選択してください:" -ForegroundColor Yellow
        Write-Host "  1: H.264 (AVC) - 互換性重視 [デフォルト]"
        Write-Host "  2: H.265 (HEVC) - 高画質 / 小容量 [-enableH265]"
        $codecChoice = Read-Host "選択 [1-2] (デフォルト: 1)"
        switch ($codecChoice.Trim()) {
            '2' { $Codec = 'H265' }
            default { $Codec = 'H264' }
        }
    }

    # 3. Container selection
    if ([string]::IsNullOrWhiteSpace($Container)) {
        Write-Host "`n[3] 出力ファイル形式 (コンテナ) を選択してください:" -ForegroundColor Yellow
        Write-Host "  1: MP4 (.mp4) - 汎用・YouTube・Googleフォト・VR標準 [デフォルト]"
        Write-Host "  2: MOV (.mov) - QuickTime / Apple互換"
        $containerChoice = Read-Host "選択 [1-2] (デフォルト: 1)"
        switch ($containerChoice.Trim()) {
            '2' { $Container = 'MOV' }
            default { $Container = 'MP4' }
        }
    }

    # 4. Audio Codec selection
    if ([string]::IsNullOrWhiteSpace($AudioCodec)) {
        if ($hasMovieConverter) {
            Write-Host "`n[4] 空間音声 (Ambisonics 4ch) のコーデックを選択してください:" -ForegroundColor Yellow
            Write-Host "  1: FLAC (可逆圧縮 / 音質劣化ゼロ・音声容量約75%削減) [推奨/デフォルト]"
            Write-Host "  2: PCM (非圧縮 3072kbps / Movie Converter標準)"
            Write-Host "  3: 通常ステレオ音声 (空間音声なし)"
            $audioChoice = Read-Host "選択 [1-3] (デフォルト: 1)"
            switch ($audioChoice.Trim()) {
                '2' { $AudioCodec = 'PCM' }
                '3' { $AudioCodec = 'Stereo' }
                default { $AudioCodec = 'FLAC' }
            }
        } else {
            $AudioCodec = 'Stereo'
        }
    }

    # 5. Encoder selection
    if ([string]::IsNullOrWhiteSpace($Encoder)) {
        Write-Host "`n[5] エンコーダー (GPUアクセラレーション) を選択してください:" -ForegroundColor Yellow
        Write-Host "  1: 自動検出 (DualfishBlenderに任せる) [デフォルト]"
        Write-Host "  2: NVIDIA NVENC (GeForce RTX/GTX 高速GPUエンコード) [-encodeFFmpeg:nvenc]"
        Write-Host "  3: Intel QuickSync (QSV ハードウェアエンコード) [-encodeFFmpeg:qsv]"
        Write-Host "  4: CPU ソフトウェアエンコード [-encodeFFmpeg:libx]"
        $encChoice = Read-Host "選択 [1-4] (デフォルト: 1)"
        switch ($encChoice.Trim()) {
            '2' { $Encoder = 'NVENC' }
            '3' { $Encoder = 'QSV' }
            '4' { $Encoder = 'CPU' }
            default { $Encoder = 'Auto' }
        }
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
}

# Set defaults if still empty
if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = 'Spatial' }
if ([string]::IsNullOrWhiteSpace($Codec)) { $Codec = 'H264' }
if ([string]::IsNullOrWhiteSpace($Container)) { $Container = 'MP4' }
if ([string]::IsNullOrWhiteSpace($AudioCodec)) {
    $AudioCodec = if ($hasMovieConverter) { 'FLAC' } else { 'Stereo' }
}
if ([string]::IsNullOrWhiteSpace($Encoder)) { $Encoder = 'Auto' }
#endregion

#region Build Command Options
$optionList = [System.Collections.Generic.List[string]]::new()

# Mode option
switch ($Mode) {
    'Spatial' { $optionList.Add("-stabilize:-image") }
    'Camera'  { $optionList.Add("-stabilize:off") }
    'Lock'    { $optionList.Add("-stabilize:lock") }
}

# Codec option
if ($Codec -eq 'H265') {
    $optionList.Add("-enableH265")
}

# Encoder option
switch ($Encoder) {
    'NVENC' { $optionList.Add("-encodeFFmpeg:nvenc") }
    'QSV'   { $optionList.Add("-encodeFFmpeg:qsv") }
    'CPU'   { $optionList.Add("-encodeFFmpeg:libx") }
    'AMF'   { $optionList.Add("-encodeFFmpeg:amf") }
}

$optionsStr = $optionList -join " "
#endregion

#region Spatial Audio Converter Helper
function Invoke-ExtractSpatialWav {
    param (
        [string]$McDir,
        [string]$InputMp4,
        [string]$TempWav,
        [string]$TempMov
    )
    $runnerScript = @"
Environment.CurrentDirectory = '$($McDir.Replace('\', '\\'))';
`$asm = [System.Reflection.Assembly]::LoadFrom(Join-Path '$($McDir.Replace('\', '\\'))' 'RICOH THETA Movie Converter.exe')
`$t = `$asm.GetType('Ricoh_Mp4Converter.Mp4Converter')
`$instance = [System.Activator]::CreateInstance(`$t)
`$initM = `$t.GetMethod('InitializeFfmpeg')
if (`$initM) { `$initM.Invoke(`$instance, `$null) }
`$convM = `$t.GetMethod('ConvertFile')
`$res = `$convM.Invoke(`$instance, @('$($InputMp4.Replace('\', '\\'))', '$($TempWav.Replace('\', '\\'))', '$($TempMov.Replace('\', '\\'))'))
exit [int]`$res
"@
    $x86PowerShell = Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $x86PowerShell)) {
        $x86PowerShell = "powershell.exe"
    }

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $x86PowerShell
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$runnerScript`""
    $pinfo.WorkingDirectory = $McDir
    $pinfo.UseShellExecute = $false
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.WaitForExit()
    return $proc.ExitCode
}
#endregion

#region Batch Execution - Videos
if ($videoFiles.Count -gt 0) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "動画変換設定:" -ForegroundColor Green
    Write-Host "  - スタビライズ : $Mode ($($optionList[0]))" -ForegroundColor White
    Write-Host "  - コーデック   : $Codec" -ForegroundColor White
    Write-Host "  - コンテナ形式 : $Container (.$($Container.ToLowerInvariant()))" -ForegroundColor White
    Write-Host "  - 音声モード   : $AudioCodec $(if ($AudioCodec -ne 'Stereo') { '(4ch 空間音声 Ambisonics)' })" -ForegroundColor White
    Write-Host "  - エンコーダー : $Encoder" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan

    $vIdx = 0
    foreach ($srcFile in $videoFiles) {
        $vIdx++
        $srcItem = Get-Item $srcFile
        $dir = if ($OutputDir) { $OutputDir } else { $srcItem.DirectoryName }
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name)
        $ext = "." + $Container.ToLowerInvariant()
        $dstFile = [System.IO.Path]::Combine($dir, "${baseName}_corrected$ext")

        Write-Host "`n[動画 $vIdx/$($videoFiles.Count)] 処理開始: $($srcItem.Name)" -ForegroundColor Cyan
        Write-Host "  最終出力先: $dstFile" -ForegroundColor Gray

        if (Test-Path $dstFile) {
            Remove-Item $dstFile -Force
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        if ($AudioCodec -in 'FLAC', 'PCM' -and $hasMovieConverter) {
            # Intermediate stitch file in temp directory
            $tempStitch = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "theta_stitch_${baseName}_$([System.Guid]::NewGuid().ToString('N')).mp4")
            $tempWav = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "theta_audio_${baseName}_$([System.Guid]::NewGuid().ToString('N')).wav")
            $tempMov = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "theta_mov_${baseName}_$([System.Guid]::NewGuid().ToString('N')).mov")

            Write-Host "  (1/3) 映像天頂補正スティッチ実行中..." -ForegroundColor Yellow
            $arguments = "$optionsStr `"$($srcItem.FullName)`" `"$tempStitch`""
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $blenderPath
            $pinfo.Arguments = $arguments
            $pinfo.WorkingDirectory = $resourcesPath
            $pinfo.UseShellExecute = $false
            $procBlender = [System.Diagnostics.Process]::Start($pinfo)
            $procBlender.WaitForExit()

            if ($procBlender.ExitCode -eq 0 -and (Test-Path $tempStitch)) {
                Write-Host "  (2/3) 4ch 空間音声(Ambisonics AmbiX)展開中..." -ForegroundColor Yellow
                $mcExit = Invoke-ExtractSpatialWav -McDir $movieConverterDir -InputMp4 $tempStitch -TempWav $tempWav -TempMov $tempMov

                Write-Host "  (3/3) 映像 + 4ch 空間音声($AudioCodec)結合中..." -ForegroundColor Yellow

                # Audio encoding parameters
                # Use -f mp4 to allow 4ch FLAC in both .mp4 and .mov container targets
                $audioParams = ""
                $fmtParam = ""
                switch ($AudioCodec) {
                    'FLAC' {
                        $audioParams = "-c:a flac -channel_layout 4.0"
                        $fmtParam = "-f mp4"
                    }
                    'PCM' {
                        $audioParams = "-c:a pcm_s16le"
                    }
                }

                # If PCM in MOV was produced directly by tempMov, move it
                if ($AudioCodec -eq 'PCM' -and $Container -eq 'MOV' -and (Test-Path $tempMov)) {
                    Move-Item $tempMov $dstFile -Force
                    $muxSuccess = $true
                } elseif (Test-Path $tempWav) {
                    # Mux tempStitch video + tempWav 4ch audio with desired codec
                    $ffmpegCmd = "ffmpeg -i `"$tempStitch`" -i `"$tempWav`" -map 0:v:0 -map 1:a:0 -c:v copy $audioParams $fmtParam `"$dstFile`" -y -loglevel error"
                    cmd.exe /c $ffmpegCmd
                    $muxSuccess = (Test-Path $dstFile)
                } elseif (Test-Path $tempMov) {
                    $ffmpegCmd = "ffmpeg -i `"$tempMov`" -c:v copy $audioParams $fmtParam `"$dstFile`" -y -loglevel error"
                    cmd.exe /c $ffmpegCmd
                    $muxSuccess = (Test-Path $dstFile)
                } else {
                    $muxSuccess = $false
                }

                # Clean up intermediate temporary files immediately to minimize SSD usage
                Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
                Remove-Item $tempWav -Force -ErrorAction SilentlyContinue
                Remove-Item $tempMov -Force -ErrorAction SilentlyContinue

                if ($muxSuccess -and (Test-Path $dstFile)) {
                    # Copy all time metadata
                    exiftool -TagsFromFile "$($srcItem.FullName)" -time:all -overwrite_original "$dstFile" *>$null
                    $dstItem = Get-Item $dstFile
                    $dstItem.CreationTime = $srcItem.CreationTime
                    $dstItem.LastWriteTime = $srcItem.LastWriteTime
                    $dstItem.LastAccessTime = $srcItem.LastAccessTime
                    $stopwatch.Stop()
                    Write-Host "  [OK] 完了 ($([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))秒) - 4ch $AudioCodec 空間音声・タイムスタンプ同期完了" -ForegroundColor Green
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
                $dstItem.CreationTime = $srcItem.CreationTime
                $dstItem.LastWriteTime = $srcItem.LastWriteTime
                $dstItem.LastAccessTime = $srcItem.LastAccessTime
                Write-Host "  [OK] 変換完了 ($([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))秒) - タイムスタンプ同期完了" -ForegroundColor Green
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
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name)
        $dstFile = [System.IO.Path]::Combine($dir, "${baseName}_corrected.jpg")

        Write-Host "`n[静止画 $imgIdx/$($imageFiles.Count)] 水平補正中: $($srcItem.Name)" -ForegroundColor Cyan
        Write-Host "  出力先: $dstFile" -ForegroundColor Gray

        if (Test-Path $dstFile) {
            Remove-Item $dstFile -Force
        }

        # Apply v360 level correction
        $ffCmd = "ffmpeg -i `"$($srcItem.FullName)`" -vf `"v360=e:e:pitch=-3.0:roll=3.5`" -q:v 2 `"$dstFile`" -y -loglevel error"
        cmd.exe /c $ffCmd

        if (Test-Path $dstFile) {
            # Copy all EXIF/XMP tags
            exiftool -TagsFromFile "$($srcItem.FullName)" -all:all -overwrite_original "$dstFile" *>$null
            $dstItem = Get-Item $dstFile
            $dstItem.CreationTime = $srcItem.CreationTime
            $dstItem.LastWriteTime = $srcItem.LastWriteTime
            $dstItem.LastAccessTime = $srcItem.LastAccessTime
            Write-Host "  [OK] 水平化完了 - 360度パノラマタグ・タイムスタンプ同期完了" -ForegroundColor Green
        } else {
            Write-Error "  [NG] 静止画の水平補正に失敗しました。"
        }
    }
}
#endregion

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "すべての処理が完了しました (動画: $($videoFiles.Count) 件, 静止画: $($imageFiles.Count) 件)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
