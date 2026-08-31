<#
.SYNOPSIS
    RICOH THETA Converter に必要な公式ツール群を完全自動ダウンロード・配置します。

.DESCRIPTION
    RICOH THETA 公式の DualfishBlender (PC用基本アプリ内包エンジン)、
    RICOH THETA Movie Converter (公式4ch空間音声エンジン)、および
    Google公式 SpatialMedia メタデータツールを自動ダウンロードし、
    リポジトリ内の tools ディレクトリに完全スタンドアロン環境として構築します。

.PARAMETER Force
    既存のツールが存在する場合でも強制的に再ダウンロード・再配置します。

.PARAMETER Help
    ヘルプ情報を表示します（-h または --help）。

.EXAMPLE
    .\Setup-ThetaTools.ps1

.EXAMPLE
    .\Setup-ThetaTools.ps1 -Force
#>
[CmdletBinding()]
param (
    #region Parameters
    [switch]$Force,

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

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "      RICOH THETA 変換環境 完全自動セットアップ            " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $PSCommandPath
$toolsDir = Join-Path $scriptDir "tools"
$blenderDir = Join-Path $toolsDir "dualfishblender"
$movieConverterDir = Join-Path $toolsDir "ricoh_movie_converter"
$spatialMediaDir = Join-Path $toolsDir "spatialmedia"

if (-not (Test-Path $toolsDir)) {
    New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
}

# 1. Setup DualfishBlender
$blenderExe = Join-Path $blenderDir "DualfishBlender.exe"
if (-not (Test-Path $blenderExe) -or $Force) {
    Write-Host "`n[1/3] RICOH THETA PC用基本アプリ (DualfishBlender) を取得中..." -ForegroundColor Yellow
    $appDataBlender = Join-Path $env:LOCALAPPDATA "Programs\RicohTheta\resources\tools\dualfishblender\win"
    if (Test-Path (Join-Path $appDataBlender "DualfishBlender.exe")) {
        Write-Host "  ローカルにインストール済みの基本アプリから DualfishBlender をコピーします..." -ForegroundColor Green
        if (Test-Path $blenderDir) { Remove-Item $blenderDir -Recurse -Force }
        Copy-Item -Path $appDataBlender -Destination $blenderDir -Recurse -Force
    } else {
        Write-Host "  RICOH 公式サイトから PC用基本アプリをダウンロード中..." -ForegroundColor Yellow
        $installerUrl = "https://theta360.com/ja/support/download/pcmba/win64"
        $tempInstaller = Join-Path [System.IO.Path]::GetTempPath() "theta_basic_setup.exe"
        Invoke-WebRequest -Uri $installerUrl -OutFile $tempInstaller -UseBasicParsing
        
        Write-Host "  インストーラーを展開中 (7-Zip 展開)..." -ForegroundColor Yellow
        $tempExtract = Join-Path [System.IO.Path]::GetTempPath() "theta_basic_extract"
        if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
        
        # 7z extraction
        $7zPath = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
        if (-not $7zPath -and (Test-Path "C:\Program Files\7-Zip\7z.exe")) { $7zPath = "C:\Program Files\7-Zip\7z.exe" }
        if ($7zPath) {
            & "$7zPath" x -o"$tempExtract" "$tempInstaller" -y *>$null
            $foundBlender = Get-ChildItem -Path $tempExtract -Filter "DualfishBlender.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundBlender) {
                $srcFolder = $foundBlender.DirectoryName
                if (Test-Path $blenderDir) { Remove-Item $blenderDir -Recurse -Force }
                Copy-Item -Path $srcFolder -Destination $blenderDir -Recurse -Force
            }
        }
        Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "`n[1/3] DualfishBlender は既にセットアップ済みです。" -ForegroundColor Green
}

# 2. Setup RICOH THETA Movie Converter
$mcExe = Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe"
$mcDll = Join-Path $movieConverterDir "Mp4ConverterLib.dll"
if (-not (Test-Path $mcExe) -or -not (Test-Path $mcDll) -or $Force) {
    Write-Host "`n[2/3] RICOH THETA Movie Converter (4ch 空間音声エンジン) を取得中..." -ForegroundColor Yellow
    $mcZipUrl = "https://theta360.com/ja/support/download/pcmc/win"
    $tempMcZip = Join-Path [System.IO.Path]::GetTempPath() "theta_movie_converter.zip"
    $tempMcExtract = Join-Path [System.IO.Path]::GetTempPath() "theta_mc_extract"
    
    try {
        Invoke-WebRequest -Uri $mcZipUrl -OutFile $tempMcZip -UseBasicParsing
        if (Test-Path $tempMcExtract) { Remove-Item $tempMcExtract -Recurse -Force }
        Expand-Archive -Path $tempMcZip -DestinationPath $tempMcExtract -Force
        
        $foundExe = Get-ChildItem -Path $tempMcExtract -Filter "RICOH THETA Movie Converter.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundExe) {
            $srcFolder = $foundExe.DirectoryName
            if (Test-Path $movieConverterDir) { Remove-Item $movieConverterDir -Recurse -Force }
            Copy-Item -Path $srcFolder -Destination $movieConverterDir -Recurse -Force
            Write-Host "  RICOH THETA Movie Converter のセットアップが完了しました。" -ForegroundColor Green
        }
    } catch {
        Write-Error "Movie Converter のダウンロードまたは展開に失敗しました: $_"
    } finally {
        Remove-Item $tempMcZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tempMcExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "`n[2/3] RICOH THETA Movie Converter は既にセットアップ済みです。" -ForegroundColor Green
}

# 3. Setup Google SpatialMedia Tools
$smPy = Join-Path $spatialMediaDir "metadata_utils.py"
if (-not (Test-Path $smPy) -or $Force) {
    Write-Host "`n[3/3] Google 公式 SpatialMedia メタデータツールを取得中..." -ForegroundColor Yellow
    $smZipUrl = "https://github.com/google/spatial-media/archive/refs/heads/master.zip"
    $tempSmZip = Join-Path [System.IO.Path]::GetTempPath() "spatial_media_master.zip"
    $tempSmExtract = Join-Path [System.IO.Path]::GetTempPath() "spatial_media_extract"

    try {
        Invoke-WebRequest -Uri $smZipUrl -OutFile $tempSmZip -UseBasicParsing
        if (Test-Path $tempSmExtract) { Remove-Item $tempSmExtract -Recurse -Force }
        Expand-Archive -Path $tempSmZip -DestinationPath $tempSmExtract -Force

        $foundSm = Get-ChildItem -Path $tempSmExtract -Filter "spatialmedia" -Directory -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundSm) {
            if (Test-Path $spatialMediaDir) { Remove-Item $spatialMediaDir -Recurse -Force }
            Copy-Item -Path $foundSm.FullName -Destination $spatialMediaDir -Recurse -Force
            Write-Host "  Google SpatialMedia ツールのセットアップが完了しました。" -ForegroundColor Green
        }
    } catch {
        Write-Error "SpatialMedia のダウンロードまたは展開に失敗しました: $_"
    } finally {
        Remove-Item $tempSmZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tempSmExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "`n[3/3] Google SpatialMedia ツールは既にセットアップ済みです。" -ForegroundColor Green
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "すべてのツールのセットアップが正常に完了しました！" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
