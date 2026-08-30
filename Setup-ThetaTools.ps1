<#
.SYNOPSIS
    RICOH公式インストーラーから必要な変換エンジン・バイナリのみを自動抽出してセットアップします。

.DESCRIPTION
    RICOH THETA PC基本アプリのインストーラー (RICOH THETA Setup.exe) および
    RICOH THETA Movie Converter のインストーラー (RICOH_THETA_Movie_Converter_ja.zip) から、
    動画変換・天頂補正スティッチ・4ch空間音声展開に必要なバイナリファイルのみを自動抽出し、
    ローカルの tools/ フォルダ配下にポータブル環境として構築します。
    さらに、PATH 上にあるフル機能版 FFmpeg (NVENC/QSV対応) で同梱の ffmpeg64 を自動アップグレードします。
    公式インストーラーは著作権・ライセンス保護のため本リポジトリには含まれていませんが、
    本スクリプトを実行することで安全にスタンドアロン変換環境を構築できます。

.PARAMETER ThetaSetupPath
    RICOH THETA 基本アプリのインストーラーパス (RICOH THETA Setup.exe)。

.PARAMETER MovieConverterZipPath
    RICOH THETA Movie Converter の ZIP パス (RICOH_THETA_Movie_Converter_ja.zip)。

.PARAMETER Help
    ヘルプ情報を表示します (-h または --help)。

.EXAMPLE
    .\Setup-ThetaTools.ps1

.EXAMPLE
    .\Setup-ThetaTools.ps1 -ThetaSetupPath ".\RICOH THETA Setup.exe"

.EXAMPLE
    .\Setup-ThetaTools.ps1 -h
#>
[CmdletBinding()]
param (
    #region Parameters
    [Parameter(Position = 0)]
    [string]$ThetaSetupPath,

    [Parameter(Position = 1)]
    [string]$MovieConverterZipPath,

    [Alias('h', '-help')]
    [switch]$Help
    #endregion
)

#region Help Handling
if ($Help) {
    Get-Help -Name $PSCommandPath -Full
    exit 0
}
#endregion

#region Environment Initialization
$scriptDir = Split-Path -Parent $PSCommandPath
$toolsDir = Join-Path $scriptDir "tools"
$blenderDstDir = Join-Path $toolsDir "dualfishblender"
$movieConverterDstDir = Join-Path $toolsDir "ricoh_movie_converter"

if (-not (Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
if (-not (Test-Path $blenderDstDir)) { New-Item -ItemType Directory -Path $blenderDstDir -Force | Out-Null }
if (-not (Test-Path $movieConverterDstDir)) { New-Item -ItemType Directory -Path $movieConverterDstDir -Force | Out-Null }

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   RICOH THETA 変換エンジン 自動抽出・セットアップツール   " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
#endregion

#region 1. Setup DualfishBlender (RICOH THETA App)
$installedBlenderDir = Join-Path $env:LOCALAPPDATA "Programs\RicohTheta\resources\tools\dualfishblender\win"
if (Test-Path (Join-Path $installedBlenderDir "DualfishBlender.exe")) {
    Write-Host "[1/2] インストール済み RICOH THETA アプリから DualfishBlender をコピー中..." -ForegroundColor Yellow
    Copy-Item -Path "$installedBlenderDir\*" -Destination $blenderDstDir -Recurse -Force
    Write-Host "  [OK] DualfishBlender の配置が完了しました。" -ForegroundColor Green
} else {
    # Search for Setup.exe
    $candidates = @(
        $ThetaSetupPath,
        (Join-Path $scriptDir "RICOH THETA Setup.exe"),
        (Join-Path $env:USERPROFILE "Downloads\RICOH THETA Setup.exe"),
        (Join-Path (Split-Path -Parent $scriptDir) "RICOH THETA Setup.exe")
    )
    $foundSetup = $null
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { $foundSetup = $c; break }
    }

    if ($foundSetup) {
        Write-Host "[1/2] $foundSetup から DualfishBlender を抽出中..." -ForegroundColor Yellow
        $tempExtract = Join-Path [System.IO.Path]::GetTempPath() "theta_setup_extract_$([System.Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

        # Extract 7z / exe
        & 7z x "$foundSetup" "-o$tempExtract" -y *>$null
        $app7z = Get-ChildItem -Path $tempExtract -Filter "app-64.7z" -Recurse | Select-Object -First 1
        if ($app7z) {
            $tempApp = Join-Path $tempExtract "app_out"
            & 7z x "$($app7z.FullName)" "-o$tempApp" -y *>$null
            $extractedWin = Join-Path $tempApp "resources\tools\dualfishblender\win"
            if (Test-Path $extractedWin) {
                Copy-Item -Path "$extractedWin\*" -Destination $blenderDstDir -Recurse -Force
                Write-Host "  [OK] インストーラーからの抽出が完了しました。" -ForegroundColor Green
            }
        }
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  [!] RICOH THETA Setup.exe が見つかりませんでした (手動配置またはダウンロードが必要です)。" -ForegroundColor DarkYellow
    }
}

# Auto-upgrade ffmpeg64 with full-featured system ffmpeg (NVENC / QSV support)
$targetBundledFfmpeg = Join-Path $blenderDstDir "ffmpeg64\ffmpeg.exe"
if (Test-Path $targetBundledFfmpeg) {
    try {
        $sysFfmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
        if ($sysFfmpeg) {
            Copy-Item -Path $sysFfmpeg.Source -Destination $targetBundledFfmpeg -Force
            Write-Host "  [OK] システムのフル機能版 FFmpeg (NVENC/QSV対応) でアップグレード完了。" -ForegroundColor Green
        }
    } catch { }
}
#endregion

#region 2. Setup RICOH THETA Movie Converter
$mcZipCandidates = @(
    $MovieConverterZipPath,
    (Join-Path $scriptDir "RICOH_THETA_Movie_Converter_ja.zip"),
    (Join-Path $env:USERPROFILE "Downloads\RICOH_THETA_Movie_Converter_ja.zip"),
    (Join-Path (Split-Path -Parent $scriptDir) "RICOH_THETA_Movie_Converter_ja.zip")
)
$foundMcZip = $null
foreach ($c in $mcZipCandidates) {
    if ($c -and (Test-Path $c)) { $foundMcZip = $c; break }
}

if ($foundMcZip) {
    Write-Host "[2/2] $foundMcZip から Movie Converter を展開中..." -ForegroundColor Yellow
    $tempMcExtract = Join-Path [System.IO.Path]::GetTempPath() "theta_mc_extract_$([System.Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempMcExtract -Force | Out-Null

    Expand-Archive -Path $foundMcZip -DestinationPath $tempMcExtract -Force
    $msiFile = Get-ChildItem -Path $tempMcExtract -Filter "*.msi" -Recurse | Select-Object -First 1
    if ($msiFile) {
        $msiOut = Join-Path $tempMcExtract "msi_out"
        Start-Process msiexec.exe -ArgumentList "/a `"$($msiFile.FullName)`" /qn TARGETDIR=`"$msiOut`"" -Wait
        $mcFiles = Get-ChildItem -Path $msiOut -Filter "RICOH THETA Movie Converter.exe" -Recurse | Select-Object -First 1
        if ($mcFiles) {
            $mcSrcDir = $mcFiles.DirectoryName
            Copy-Item -Path "$mcSrcDir\*" -Destination $movieConverterDstDir -Recurse -Force
            Write-Host "  [OK] Movie Converter の抽出が完了しました。" -ForegroundColor Green
        }
    }
    Remove-Item -Path $tempMcExtract -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  [!] RICOH_THETA_Movie_Converter_ja.zip が見つかりませんでした (手動配置またはダウンロードが必要です)。" -ForegroundColor DarkYellow
}
#endregion

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "セットアップ処理が完了しました。" -ForegroundColor Green
Write-Host "tools/ フォルダの状態:" -ForegroundColor White
Write-Host "  - DualfishBlender : $(if (Test-Path (Join-Path $blenderDstDir 'DualfishBlender.exe')) { 'Ready (OK)' } else { 'Missing' })" -ForegroundColor $(if (Test-Path (Join-Path $blenderDstDir 'DualfishBlender.exe')) { 'Green' } else { 'Red' })
Write-Host "  - Movie Converter : $(if (Test-Path (Join-Path $movieConverterDstDir 'RICOH THETA Movie Converter.exe')) { 'Ready (OK)' } else { 'Missing' })" -ForegroundColor $(if (Test-Path (Join-Path $movieConverterDstDir 'RICOH THETA Movie Converter.exe')) { 'Green' } else { 'Red' })
Write-Host "============================================================" -ForegroundColor Cyan
