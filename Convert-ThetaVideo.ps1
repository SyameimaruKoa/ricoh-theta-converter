<#
.SYNOPSIS
    RICOH THETA??????????????????????4ch????(FLAC)???????????

.DESCRIPTION
    RICOH THETA???????DualfishBlender.exe???? RICOH THETA Movie Converter ?????
    ?????????????????????????360?Equirectangular?????????
    4ch ?????First-Order Ambisonics AmbiX + SA3D?? FLAC(????)/PCM(???)???
    MP4 / MOV ?????????????/???????/???????????H.265??????GPU?????????
    SSD??????????????????????????
    ????????????EXIF????????????????Google???????????????
    ???????.JPG??????????????????????????????????

.PARAMETER Path
    ?????RICOH THETA????????????????????????????????????

.PARAMETER Mode
    ???????????????Spatial: ?????? / Camera: ??????? / Lock: ???????

.PARAMETER Codec
    ??????????H264 / H265??

.PARAMETER Encoder
    ?????????Auto / NVENC / QSV / CPU / AMF??

.PARAMETER Container
    ?????????MP4 / MOV??

.PARAMETER AudioCodec
    ????????FLAC: ??????? / PCM: ??? / Stereo: ????????

.PARAMETER OutputDir
    ????????????????????????????

.PARAMETER NonInteractive
    ???????????????????????????????????????????

.PARAMETER Help
    ????????????-h ??? --help??

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
    Write-Error "DualfishBlender.exe not found in local tools or AppData."
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
    Write-Host "No input video or image files provided." -ForegroundColor Yellow
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
    Write-Host "        RICOH THETA ????????????????        " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "??????: $($videoFiles.Count) ?, ???????: $($imageFiles.Count) ?" -ForegroundColor White
    foreach ($f in $inputFiles) {
        Write-Host "  - $([System.IO.Path]::GetFileName($f))" -ForegroundColor Gray
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "??????????? : ?? (DualfishBlender)" -ForegroundColor Green
    Write-Host "????????       : $(if ($hasMovieConverter) { '?? (Ambisonics AmbiX + SA3D)' } else { '??? (??????)' })" -ForegroundColor Green
    Write-Host "?????GPU??      : $detectedGpu" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    # 1. Mode selection
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        Write-Host "`n[1] ?????? / ????????????????:" -ForegroundColor Yellow
        Write-Host "  1: ?????? (???????? + ??????, ????OFF) [-stabilize:-image] [??/?????]"
        Write-Host "  2: ??????? (???????? + ??????????) [-stabilize:off]"
        Write-Host "  3: ??????? (???????? + ?????????????) [-stabilize:lock]"
        $modeChoice = Read-Host "?? [1-3] (?????: 1)"
        switch ($modeChoice.Trim()) {
            '2' { $Mode = 'Camera' }
            '3' { $Mode = 'Lock' }
            default { $Mode = 'Spatial' }
        }
    }

    # 2. Codec selection
    if ([string]::IsNullOrWhiteSpace($Codec)) {
        Write-Host "`n[2] ??????????????????:" -ForegroundColor Yellow
        Write-Host "  1: H.264 (AVC) - ????? [?????]"
        Write-Host "  2: H.265 (HEVC) - ??? / ??? [-enableH265]"
        $codecChoice = Read-Host "?? [1-2] (?????: 1)"
        switch ($codecChoice.Trim()) {
            '2' { $Codec = 'H265' }
            default { $Codec = 'H264' }
        }
    }

    # 3. Container selection
    if ([string]::IsNullOrWhiteSpace($Container)) {
        Write-Host "`n[3] ???????? (????) ?????????:" -ForegroundColor Yellow
        Write-Host "  1: MP4 (.mp4) - ???YouTube?Google????VR?? [?????]"
        Write-Host "  2: MOV (.mov) - QuickTime / Apple??"
        $containerChoice = Read-Host "?? [1-2] (?????: 1)"
        switch ($containerChoice.Trim()) {
            '2' { $Container = 'MOV' }
            default { $Container = 'MP4' }
        }
    }

    # 4. Audio Codec selection
    if ([string]::IsNullOrWhiteSpace($AudioCodec)) {
        if ($hasMovieConverter) {
            Write-Host "`n[4] ???? (Ambisonics 4ch) ???????????????:" -ForegroundColor Yellow
            Write-Host "  1: FLAC (???? / ????????????75%??) [??/?????]"
            Write-Host "  2: PCM (??? 3072kbps / Movie Converter??)"
            Write-Host "  3: ???????? (??????)"
            $audioChoice = Read-Host "?? [1-3] (?????: 1)"
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
        Write-Host "`n[5] ?????? (GPU?????????) ?????????:" -ForegroundColor Yellow
        Write-Host "  1: ???? (DualfishBlender????) [?????]"
        Write-Host "  2: NVIDIA NVENC (GeForce RTX/GTX ??GPU?????) [-encodeFFmpeg:nvenc]"
        Write-Host "  3: Intel QuickSync (QSV ???????????) [-encodeFFmpeg:qsv]"
        Write-Host "  4: CPU ??????????? [-encodeFFmpeg:libx]"
        $encChoice = Read-Host "?? [1-4] (?????: 1)"
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
Environment.CurrentDirectory = '$($McDir.Replace('', '\'))';
`$asm = [System.Reflection.Assembly]::LoadFrom(Join-Path '$($McDir.Replace('', '\'))' 'RICOH THETA Movie Converter.exe')
`$t = `$asm.GetType('Ricoh_Mp4Converter.Mp4Converter')
`$instance = [System.Activator]::CreateInstance(`$t)
`$initM = `$t.GetMethod('InitializeFfmpeg')
if (`$initM) { `$initM.Invoke(`$instance, `$null) }
`$convM = `$t.GetMethod('ConvertFile')
`$res = `$convM.Invoke(`$instance, @('$($InputMp4.Replace('', '\'))', '$($TempWav.Replace('', '\'))', '$($TempMov.Replace('', '\'))'))
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
    Write-Host "??????:" -ForegroundColor Green
    Write-Host "  - ?????? : $Mode ($($optionList[0]))" -ForegroundColor White
    Write-Host "  - ?????   : $Codec" -ForegroundColor White
    Write-Host "  - ?????? : $Container (.$($Container.ToLowerInvariant()))" -ForegroundColor White
    Write-Host "  - ?????   : $AudioCodec $(if ($AudioCodec -ne 'Stereo') { '(4ch ???? Ambisonics)' })" -ForegroundColor White
    Write-Host "  - ?????? : $Encoder" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan

    $vIdx = 0
    foreach ($srcFile in $videoFiles) {
        $vIdx++
        $srcItem = Get-Item $srcFile
        $dir = if ($OutputDir) { $OutputDir } else { $srcItem.DirectoryName }
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name)
        $ext = "." + $Container.ToLowerInvariant()
        $dstFile = [System.IO.Path]::Combine($dir, "${baseName}_corrected$ext")

        Write-Host "`n[?? $vIdx/$($videoFiles.Count)] ????: $($srcItem.Name)" -ForegroundColor Cyan
        Write-Host "  ?????: $dstFile" -ForegroundColor Gray

        if (Test-Path $dstFile) {
            Remove-Item $dstFile -Force
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        if ($AudioCodec -in 'FLAC', 'PCM' -and $hasMovieConverter) {
            # Intermediate stitch file in temp directory
            $tempStitch = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "theta_stitch_${baseName}_$([System.Guid]::NewGuid().ToString('N')).mp4")
            $tempWav = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "theta_audio_${baseName}_$([System.Guid]::NewGuid().ToString('N')).wav")
            $tempMov = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "theta_mov_${baseName}_$([System.Guid]::NewGuid().ToString('N')).mov")

            Write-Host "  (1/3) ??????????????..." -ForegroundColor Yellow
            $arguments = "$optionsStr `"$($srcItem.FullName)`" `"$tempStitch`""
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $blenderPath
            $pinfo.Arguments = $arguments
            $pinfo.WorkingDirectory = $resourcesPath
            $pinfo.UseShellExecute = $false
            $procBlender = [System.Diagnostics.Process]::Start($pinfo)
            $procBlender.WaitForExit()

            if ($procBlender.ExitCode -eq 0 -and (Test-Path $tempStitch)) {
                Write-Host "  (2/3) 4ch ????(Ambisonics AmbiX)???..." -ForegroundColor Yellow
                $mcExit = Invoke-ExtractSpatialWav -McDir $movieConverterDir -InputMp4 $tempStitch -TempWav $tempWav -TempMov $tempMov

                Write-Host "  (3/3) ?? + 4ch ????($AudioCodec)???..." -ForegroundColor Yellow

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
                    Write-Host "  [OK] ?? ($([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))?) - 4ch $AudioCodec ????????????????" -ForegroundColor Green
                } else {
                    Write-Error "  [NG] ???????????????"
                }
            } else {
                Remove-Item $tempStitch -Force -ErrorAction SilentlyContinue
                Write-Error "  [NG] DualfishBlender ????????????????? (ExitCode: $($procBlender.ExitCode))"
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
                Write-Host "  [OK] ???? ($([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))?) - ???????????" -ForegroundColor Green
            } else {
                Write-Error "  [NG] DualfishBlender ?????????? (ExitCode: $($procBlender.ExitCode))"
            }
        }
    }
}
#endregion

#region Batch Execution - Images
if ($imageFiles.Count -gt 0) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "????????? (?????????? Pitch: -3.0?, Roll: +3.5?):" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan

    $imgIdx = 0
    foreach ($imgFile in $imageFiles) {
        $imgIdx++
        $srcItem = Get-Item $imgFile
        $dir = if ($OutputDir) { $OutputDir } else { $srcItem.DirectoryName }
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($srcItem.Name)
        $dstFile = [System.IO.Path]::Combine($dir, "${baseName}_corrected.jpg")

        Write-Host "`n[??? $imgIdx/$($imageFiles.Count)] ?????: $($srcItem.Name)" -ForegroundColor Cyan
        Write-Host "  ???: $dstFile" -ForegroundColor Gray

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
            Write-Host "  [OK] ????? - 360???????????????????" -ForegroundColor Green
        } else {
            Write-Error "  [NG] ????????????????"
        }
    }
}
#endregion

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "????????????? (??: $($videoFiles.Count) ?, ???: $($imageFiles.Count) ?)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
