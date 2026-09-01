<#
.SYNOPSIS
    変換済み動画または未加工動画から、YouTube/VR空間音声(SA3D内蔵)完全対応のMOV形式へ復元・nセッション並列一括再変換します。

.DESCRIPTION
    MP4やFLAC等の非対応形式で変換してしまったRICOH THETA動画や未加工動画（*.MP4）から、
    公式エンジン（DualfishBlender + RICOH THETA Movie Converter）を用いて、
    YouTube / Google / Meta Quest 等で100%空間音声として自動認識される公式標準 MOV (PCM 4ch + SA3D内蔵) ファイルを一括生成・復元します。
    GPU性能を最大限に引き出すため、デフォルト2セッション（-Threads n で変更可能）のマルチスレッド並列一括処理に対応しています。
    また、AndroidやGoogleフォトで発生するタイムゾーン（UTC/JST +9時間）計算ズレを解消するため、
    QuickTimeタグ（UTC）およびKeys:CreationDate（タイムゾーン付きローカル日時）を完全自動同期します。
    
    【処理内容別ファイル名サフィックス規則】
      - 空間方位固定 (推奨)   : *_er_spatial.mov
      - カメラ正面追従       : *_er_cam.mov
      - 方位完全ロック       : *_er_lock.mov
      - 手ブレ補正ON (公式)   : *_er.mov

    RAMDISK（R:\ 等）の自動検出と中間作業領域の完全RAM化、GoogleフォトJSONやEXIFからの撮影日時自動復元に対応しています。

.PARAMETER Path
    復元・変換対象の動画ファイルパス（未加工生動画 *.MP4 または変換済み動画、複数指定・ワイルドカード対応）。

.PARAMETER Mode
    スタビライズ・方位固定モード（Spatial: 空間方位固定 / Camera: カメラ正面追従 / Lock: 方位ロック / ImageBlur: 手ブレ補正ON）。

.PARAMETER Threads
    並列実行セッション数（デフォルト: 2）。

.PARAMETER TempDir
    中間ファイル作成用の一時ディレクトリ（RAMDISKなど。省略時は R:\ ドライブが存在すれば自動使用）。

.PARAMETER NonInteractive
    確認プロンプトを表示せず即時実行します。

.PARAMETER Help
    ヘルプ情報を表示します（-h または --help）。

.EXAMPLE
    .\Restore-ThetaSpatialMov.ps1 -Path .\R0010390.MP4

.EXAMPLE
    .\Restore-ThetaSpatialMov.ps1 *.MP4 -Threads 4 -NonInteractive

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

    [int]$Threads = 2,

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

if ($Threads -lt 1) { $Threads = 2 }
#endregion

#region Build Options
$stabilizeOpt = switch ($Mode) {
    'Camera'    { "-stabilize:off" }
    'Lock'      { "-stabilize:lock" }
    'ImageBlur' { "-stabilize:image" }
    default     { "-stabilize:-image" }
}

$modeSuffix = switch ($Mode) {
    'Spatial'   { "_er_spatial" }
    'Camera'    { "_er_cam" }
    'Lock'      { "_er_lock" }
    'ImageBlur' { "_er" }
    default     { "_er_spatial" }
}
#endregion

#region Worker Script Block
$restoreWorkerScriptBlock = {
    param (
        [string]$SrcFile,
        [int]$VideoIndex,
        [int]$TotalVideos,
        [string]$StabilizeOpt,
        [string]$ModeSuffix,
        [string]$WorkingTempDir,
        [string]$BlenderPath,
        [string]$ResourcesPath,
        [string]$MovieConverterDir,
        [hashtable]$SyncState
    )

    $srcItem = Get-Item $SrcFile
    $dir = $srcItem.DirectoryName
    $cleanRegex = '(_er|_spatial|_cam|_lock|_yaw[0-9\-]+|_tc[0-9\-]+|_corrected|_stitched)+$'
    $rawBaseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name) -replace $cleanRegex, ''
    
    $dstFile = [System.IO.Path]::Combine($dir, "$rawBaseName$ModeSuffix.mov")

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

    # Timestamp extraction
    $name = $srcItem.Name
    $jsonCandidates = @(
        (Join-Path $dir "$name.json"),
        (Join-Path $dir "$rawBaseName.MP4.json"),
        (Join-Path $dir "$rawBaseName.json")
    )
    $targetDt = $srcItem.LastWriteTime

    foreach ($jc in $jsonCandidates) {
        if (Test-Path $jc) {
            try {
                $jsonContent = Get-Content -Path $jc -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($jsonContent.photoTakenTime -and $jsonContent.photoTakenTime.timestamp) {
                    $tsLong = [int64]$jsonContent.photoTakenTime.timestamp
                    if ($tsLong -gt 0) {
                        $targetDt = [System.DateTimeOffset]::FromUnixTimeSeconds($tsLong).LocalDateTime
                        break
                    }
                }
            } catch { }
        }
    }

    if (Test-Path $dstFile) { Remove-Item $dstFile -Force }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $tempStitch = [System.IO.Path]::Combine($WorkingTempDir, "theta_stitch_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).mp4")
    $tempWav = [System.IO.Path]::Combine($WorkingTempDir, "theta_audio_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).wav")
    $tempMov = [System.IO.Path]::Combine($WorkingTempDir, "theta_mov_${rawBaseName}_$([System.Guid]::NewGuid().ToString('N')).mov")

    $arguments = "$StabilizeOpt `"$rawFile`" `"$tempStitch`""
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

        if ((Test-Path $tempMov) -and (Get-Item $tempMov).Length -gt 0) {
            Move-Item $tempMov $dstFile -Force

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
            Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
            Remove-Item $tempWav -Force -ErrorAction SilentlyContinue
            Remove-Item $tempMov -Force -ErrorAction SilentlyContinue

            if ($SyncState -and $SyncState.ContainsKey($VideoIndex)) {
                $SyncState[$VideoIndex].Percent = 100.0
                $SyncState[$VideoIndex].Stage = "完了"
            }

            return [PSCustomObject]@{
                Success = $true
                Message = "$($srcItem.Name) ($([Math]::Round($sw.Elapsed.TotalSeconds, 1))秒) -> $([System.IO.Path]::GetFileName($dstFile))"
            }
        } else {
            Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
            Remove-Item $tempWav -Force -ErrorAction SilentlyContinue
            Remove-Item $tempMov -Force -ErrorAction SilentlyContinue
            return [PSCustomObject]@{
                Success = $false
                Message = "$($srcItem.Name) エラー (Movie Converter 失敗)"
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
}
#endregion

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   RICOH THETA 空間音声MOV (SA3D内蔵) 復元・再変換ツール   " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "対象動画ファイル数 : $($inputFiles.Count) 件" -ForegroundColor White
Write-Host "作業領域 (TEMP)    : $tempDisplayStr" -ForegroundColor Green
Write-Host "スタビライズモード : $Mode ($modeSuffix)" -ForegroundColor Green
Write-Host "並列セッション数   : $Threads 並列" -ForegroundColor Green
Write-Host "出力形式           : MOV (.mov) [YouTube / VR 空間音声完全互換]" -ForegroundColor Green
Write-Host "空間音声エンジン   : RICOH THETA Movie Converter 公式純正" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

$totalWatch = [System.Diagnostics.Stopwatch]::StartNew()
$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $Threads)
$pool.Open()

$runspaces = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
$syncState = [Hashtable]::Synchronized(@{})
$startedSet = [System.Collections.Generic.HashSet[int]]::new()
$totalVideos = $inputFiles.Count
$completedCount = 0

$idx = 0
foreach ($srcFile in $inputFiles) {
    $idx++
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    
    [void]$ps.AddScript($restoreWorkerScriptBlock).AddParameters(@{
        SrcFile           = $srcFile
        VideoIndex        = $idx
        TotalVideos       = $totalVideos
        StabilizeOpt      = $stabilizeOpt
        ModeSuffix        = $modeSuffix
        WorkingTempDir    = $workingTempDir
        BlenderPath       = $blenderPath
        ResourcesPath     = $resourcesPath
        MovieConverterDir = $movieConverterDir
        SyncState         = $syncState
    })

    $asyncResult = $ps.BeginInvoke()
    [void]$runspaces.Add([PSCustomObject]@{
        PowerShell  = $ps
        AsyncResult = $asyncResult
        FileName    = [System.IO.Path]::GetFileName($srcFile)
        Index       = $idx
    })
}

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
        Write-Progress -Id 0 -Activity "THETA 空間音声MOV 復元" -Status "完了: $completedCount / $totalVideos 件 ($overallPct%)" -PercentComplete $overallPct
        
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

try {
    if (Test-Path $workingTempDir) {
        $remains = Get-ChildItem -Path $workingTempDir -ErrorAction SilentlyContinue
        if ($remains.Count -eq 0) { Remove-Item -Path $workingTempDir -Force -ErrorAction SilentlyContinue }
    }
} catch { }

$totalWatch.Stop()
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "すべての復元・再変換処理が完了しました ($($inputFiles.Count) 件, 総所要時間: $([Math]::Round($totalWatch.Elapsed.TotalSeconds, 1)) 秒)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
