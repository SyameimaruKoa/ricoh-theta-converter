<#
.SYNOPSIS
    変換済み動画または未加工動画から、YouTube/VR空間音声(SA3D内蔵)完全対応のMOV形式へ復元・一括再変換します。

.DESCRIPTION
    MP4やFLAC等の非対応形式で変換してしまったRICOH THETA動画や未加工動画（*.MP4）から、
    公式エンジン（DualfishBlender + RICOH THETA Movie Converter）を用いて、
    YouTube / Google / Meta Quest 等で100%空間音声として自動認識される公式標準 MOV (PCM 4ch + SA3D内蔵) ファイルを一括生成・復元します。
    出力ファイル名は公式 Movie Converter と完全に同一の命名規則（例: R0010390.MP4 -> R0010390.mov）を採用しています。
    RAMDISK（R:\ 等）の自動検出と中間作業領域の完全RAM化、GoogleフォトJSONやEXIFからの撮影日時自動復元に対応しています。

.PARAMETER Path
    復元・変換対象の動画ファイルパス（未加工生動画 *.MP4 または変換済み動画、複数指定・ワイルドカード対応）。

.PARAMETER Mode
    スタビライズ・方位固定モード（Spatial: 空間方位固定 / Camera: カメラ正面追従 / Lock: 方位ロック / ImageBlur: 手ブレ補正ON）。

.PARAMETER TempDir
    中間ファイル作成用の一時ディレクトリ（RAMDISKなど。省略時は R:\ ドライブが存在すれば自動使用）。

.PARAMETER NonInteractive
    確認プロンプトを表示せず即時実行します。

.PARAMETER Help
    ヘルプ情報を表示します（-h または --help）。

.EXAMPLE
    .\Restore-ThetaSpatialMov.ps1 -Path .\R0010390.MP4

.EXAMPLE
    .\Restore-ThetaSpatialMov.ps1 *.MP4 -NonInteractive

.EXAMPLE
    .\Restore-ThetaSpatialMov.ps1 -h
#>
[CmdletBinding()]
param (
    #region Parameters
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Path,

    [ValidateSet('Spatial', 'Camera', 'Lock', 'ImageBlur')]
    [string]$Mode = 'Spatial',

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

#region Set GPU Performance Environment Flags
$env:SHIM_MCCOMPAT = "0x0000000000000001"
$env:CUDA_VISIBLE_DEVICES = "0"
$env:__NV_PRIME_RENDER_OFFLOAD = "1"
#endregion

#region Setup RAMDISK / Working Temp Directory
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
    if ($drv) { $tempFreeGb = [Math]::Round($drv.Free / 1GB, 1) }
} catch { }

$tempDisplayStr = "$workingTempDir $(if ($isRamDisk) { '(RAMDISK 検出・SSD書き込み完全ゼロ)' }) [空き: ${tempFreeGb} GB]"
#endregion

#region Engine Discovery
$scriptDir = Split-Path -Parent $PSCommandPath
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

$movieConverterDir = Join-Path $scriptDir "tools\ricoh_movie_converter"
$hasMovieConverter = (Test-Path (Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe")) -and (Test-Path (Join-Path $movieConverterDir "Mp4ConverterLib.dll"))

if (-not $hasMovieConverter) {
    Write-Error "RICOH THETA Movie Converter が見つかりません。Setup-ThetaTools.bat を実行してセットアップを行ってください。"
    exit 1
}
#endregion

#region Timestamp Extraction Helper
function Get-MediaTrueTimestamp {
    param (
        [string]$FilePath
    )
    $fileItem = Get-Item $FilePath
    $dir = $fileItem.DirectoryName
    $name = $fileItem.Name
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($name).Replace('_corrected', '').Replace('_stitched', '')

    $jsonCandidates = @(
        (Join-Path $dir "$name.json"),
        (Join-Path $dir "$nameWithoutExt.MP4.json"),
        (Join-Path $dir "$nameWithoutExt.json")
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
            } catch { }
        }
    }

    try {
        $exifDate = (exiftool -d "%Y:%m:%d %H:%M:%S" -s3 -DateTimeOriginal -CreateDate -CreationDate -TrackCreateDate "$FilePath" 2>$null | Where-Object { $_ -match "^\d{4}:\d{2}:\d{2}" } | Select-Object -First 1)
        if ($exifDate -and ($exifDate -match "^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})")) {
            $parsedDt = [datetime]::ParseExact($exifDate.Trim(), "yyyy:MM:dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            return @{ DateTime = $parsedDt; Source = "InternalMetadata (EXIF/QuickTime)" }
        }
    } catch { }

    return @{ DateTime = $fileItem.LastWriteTime; Source = "FileSystem" }
}
#endregion

#region Official Movie Converter Invoker
function Invoke-OfficialConvert {
    param (
        [string]$McDir,
        [string]$StitchedMp4Path,
        [string]$OutWav,
        [string]$OutMov,
        [string]$WorkDir
    )
    $tempRunner = [System.IO.Path]::Combine($WorkDir, "theta_runner_$([System.Guid]::NewGuid().ToString('N')).ps1")
    $dllPathEscaped = [System.IO.Path]::Combine($McDir, "Mp4ConverterLib.dll").Replace('\', '\\')
    $mcDirEscaped = $McDir.Replace('\', '\\')
    $stitchedEscaped = $StitchedMp4Path.Replace('\', '\\')
    $wavEscaped = $OutWav.Replace('\', '\\')
    $movEscaped = $OutMov.Replace('\', '\\')

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
    $exitCode = $LASTEXITCODE

    Remove-Item $tempRunner -Force -ErrorAction SilentlyContinue
    return $exitCode
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
                if (Test-Path -Path $r.Path -PathType Leaf) { $inputFiles.Add($r.Path) }
            }
        } elseif (Test-Path -Path $p -PathType Leaf) {
            $inputFiles.Add((Get-Item $p).FullName)
        }
    }
}

if ($inputFiles.Count -eq 0) {
    Write-Host "処理対象の動画ファイルが指定されていません。" -ForegroundColor Yellow
    Get-Help -Name $PSCommandPath -Full
    exit 0
}
#endregion

#region Build Options
$stabilizeOpt = switch ($Mode) {
    'Camera'    { "-stabilize:off" }
    'Lock'      { "-stabilize:lock" }
    'ImageBlur' { "-stabilize:image" }
    default     { "-stabilize:-image" }
}
#endregion

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   RICOH THETA 空間音声MOV (SA3D内蔵) 復元・再変換ツール   " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "対象動画ファイル数 : $($inputFiles.Count) 件" -ForegroundColor White
Write-Host "作業領域 (TEMP)    : $tempDisplayStr" -ForegroundColor Green
Write-Host "出力形式           : MOV (.mov) [YouTube / VR 空間音声完全互換]" -ForegroundColor Green
Write-Host "空間音声エンジン   : RICOH THETA Movie Converter 公式純正" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

$idx = 0
foreach ($srcFile in $inputFiles) {
    $idx++
    $srcItem = Get-Item $srcFile
    $dir = $srcItem.DirectoryName
    $rawBaseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name).Replace('_corrected', '').Replace('_stitched', '')
    
    # Official naming rule: R0010390.MP4 -> R0010390.mov
    $dstFile = [System.IO.Path]::Combine($dir, "$rawBaseName.mov")

    # Find raw THETA MP4 file if input is already converted MP4
    $rawCandidates = @(
        (Join-Path $dir "$rawBaseName.MP4"),
        (Join-Path $dir "$rawBaseName.mp4"),
        $srcItem.FullName
    )
    $rawFile = $null
    foreach ($rc in $rawCandidates) {
        if (Test-Path $rc) {
            $rawFile = $rc
            break
        }
    }

    $trueTimeInfo = Get-MediaTrueTimestamp -FilePath $srcItem.FullName
    $targetDt = $trueTimeInfo.DateTime
    $timeSrcName = $trueTimeInfo.Source

    Write-Host "`n[動画 $idx/$($inputFiles.Count)] 復元処理中: $($srcItem.Name)" -ForegroundColor Cyan
    Write-Host "  元動画ソース: $(if ($rawFile) { [System.IO.Path]::GetFileName($rawFile) } else { '元動画未検出' })" -ForegroundColor Gray
    Write-Host "  撮影日時検出: $($targetDt.ToString('yyyy-MM-dd HH:mm:ss')) (ソース: $timeSrcName)" -ForegroundColor Green
    Write-Host "  出力先 MOV  : $dstFile" -ForegroundColor Gray

    if (Test-Path $dstFile) {
        Remove-Item $dstFile -Force
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $tempStitch = [System.IO.Path]::Combine($workingTempDir, "theta_stitch_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).mp4")
    $tempWav = [System.IO.Path]::Combine($workingTempDir, "theta_audio_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).wav")
    $tempMov = [System.IO.Path]::Combine($workingTempDir, "theta_mov_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).mov")

    Write-Host "  (1/2) 公式天頂補正スティッチ実行中 (DualfishBlender)..." -ForegroundColor Yellow
    $arguments = "$stabilizeOpt `"$rawFile`" `"$tempStitch`""
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $blenderPath
    $pinfo.Arguments = $arguments
    $pinfo.WorkingDirectory = $resourcesPath
    $pinfo.UseShellExecute = $false
    $procBlender = [System.Diagnostics.Process]::Start($pinfo)
    $procBlender.WaitForExit()

    if ($procBlender.ExitCode -eq 0 -and (Test-Path $tempStitch)) {
        Write-Host "  (2/2) 公式4ch空間音声MOV生成中 (RICOH THETA Movie Converter)..." -ForegroundColor Yellow
        $mcExit = Invoke-OfficialConvert -McDir $movieConverterDir -StitchedMp4Path $tempStitch -OutWav $tempWav -OutMov $tempMov -WorkDir $workingTempDir

        if ((Test-Path $tempMov) -and (Get-Item $tempMov).Length -gt 0) {
            Move-Item $tempMov $dstFile -Force

            exiftool -TagsFromFile "$rawFile" -time:all -overwrite_original "$dstFile" *>$null
            $dstItem = Get-Item $dstFile
            $dstItem.CreationTime = $targetDt
            $dstItem.LastWriteTime = $targetDt
            $dstItem.LastAccessTime = $targetDt
            $stopwatch.Stop()
            Write-Host "  [OK] 復元完了 ($([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))秒) - YouTube空間音声完全対応(SA3D内蔵) MOV生成完了" -ForegroundColor Green
        } else {
            Write-Error "  [NG] Movie Converter による空間音声MOV生成に失敗しました。"
        }
    } else {
        Write-Error "  [NG] DualfishBlender による映像スティッチに失敗しました (ExitCode: $($procBlender.ExitCode))"
    }

    Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
    Remove-Item $tempWav -Force -ErrorAction SilentlyContinue
    Remove-Item $tempMov -Force -ErrorAction SilentlyContinue
}

try {
    if (Test-Path $workingTempDir) {
        $remains = Get-ChildItem -Path $workingTempDir -ErrorAction SilentlyContinue
        if ($remains.Count -eq 0) { Remove-Item -Path $workingTempDir -Force -ErrorAction SilentlyContinue }
    }
} catch { }

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "すべての復元・再変換処理が完了しました ($($inputFiles.Count) 件)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
