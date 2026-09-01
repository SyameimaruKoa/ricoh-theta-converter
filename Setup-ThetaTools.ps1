<#
.SYNOPSIS
    RICOH THETA Converter に必要な公式ツール群をローカルインストーラーから自動展開・配置します。

.DESCRIPTION
    RICOH THETA 公式の DualfishBlender (PC用基本アプリ内包エンジン)、
    RICOH THETA Movie Converter (公式4ch空間音声エンジン)、および
    Google公式 SpatialMedia メタデータツールを展開し、
    リポジトリ内の tools ディレクトリに完全スタンドアロン環境として構築します。

.PARAMETER Force
    既存のツールが存在する場合でも強制的に再展開・再配置します。

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
    Write-Host "`n[1/3] RICOH THETA PC用基本アプリ (DualfishBlender) を展開中..." -ForegroundColor Yellow
    $localInstaller = Get-ChildItem -Path $scriptDir -Filter "*Setup*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $localInstaller) {
        $localInstaller = Get-ChildItem -Path $scriptDir -Filter "*THETA*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if (-not $localInstaller) {
        Write-Error "RICOH THETA のインストーラー (RICOH THETA Setup.exe) がリポジトリ内に見つかりません。"
    }
    else {
        Write-Host "  インストーラー ($($localInstaller.Name)) を展開中..." -ForegroundColor Green
        
        # 7-Zip の探索
        $7zPath = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
        if (-not $7zPath) {
            $candidate7z = @(
                "C:\Program Files\7-Zip\7z.exe",
                "C:\Program Files (x86)\7-Zip\7z.exe",
                "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe",
                "$env:USERPROFILE\scoop\shims\7z.exe"
            )
            foreach ($cand in $candidate7z) {
                if (Test-Path $cand) { $7zPath = $cand; break }
            }
        }

        if (-not $7zPath) {
            Write-Error "7-Zip (7z.exe) が見つかりませんでした。7-Zip をインストールするか PATH に追加してください。"
        }
        else {
            $tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) "theta_basic_extract"
            $tempBlenderExtract = Join-Path ([System.IO.Path]::GetTempPath()) "theta_blender_extract"
            if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
            if (Test-Path $tempBlenderExtract) { Remove-Item $tempBlenderExtract -Recurse -Force }

            try {
                & "$7zPath" x -o"$tempExtract" "$($localInstaller.FullName)" -y *>$null
                $foundApp7z = Get-ChildItem -Path $tempExtract -Filter "app-64.7z" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($foundApp7z) {
                    & "$7zPath" x -o"$tempBlenderExtract" "$($foundApp7z.FullName)" "resources/tools/dualfishblender/win/*" -y *>$null
                    $foundBlender = Get-ChildItem -Path $tempBlenderExtract -Filter "DualfishBlender.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($foundBlender) {
                        $srcFolder = $foundBlender.DirectoryName
                        if (Test-Path $blenderDir) { Remove-Item $blenderDir -Recurse -Force }
                        Copy-Item -Path $srcFolder -Destination $blenderDir -Recurse -Force
                        Write-Host "  DualfishBlender のセットアップが完了しました。" -ForegroundColor Green
                    }
                    else {
                        Write-Error "展開されたパッケージ内に DualfishBlender.exe が見つかりませんでした。"
                    }
                }
                else {
                    Write-Error "インストーラー内に app-64.7z が見つかりませんでした。"
                }
            }
            catch {
                Write-Error "DualfishBlender の展開に失敗しました: $_"
            }
            finally {
                if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
                if (Test-Path $tempBlenderExtract) { Remove-Item $tempBlenderExtract -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}
else {
    Write-Host "`n[1/3] DualfishBlender は既にセットアップ済みです。" -ForegroundColor Green
}

# 2. Setup RICOH THETA Movie Converter
$mcExe = Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe"
$mcDll = Join-Path $movieConverterDir "Mp4ConverterLib.dll"
if (-not (Test-Path $mcExe) -or -not (Test-Path $mcDll) -or $Force) {
    Write-Host "`n[2/3] RICOH THETA Movie Converter (4ch 空間音声エンジン) を展開中..." -ForegroundColor Yellow
    $localZip = Get-ChildItem -Path $scriptDir -Filter "*Movie_Converter*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $localZip) {
        Write-Error "RICOH THETA Movie Converter の ZIP パッケージ (*Movie_Converter*.zip) が見つかりません。"
    }
    else {
        Write-Host "  ZIP パッケージ ($($localZip.Name)) を展開中..." -ForegroundColor Green
        $tempMcExtract = Join-Path ([System.IO.Path]::GetTempPath()) "theta_mc_extract"
        $tempMsiExtract = Join-Path ([System.IO.Path]::GetTempPath()) "theta_mc_msi_extract"

        try {
            if (Test-Path $tempMcExtract) { Remove-Item $tempMcExtract -Recurse -Force }
            Expand-Archive -Path $localZip.FullName -DestinationPath $tempMcExtract -Force

            # MSI インストーラーが存在する場合は msiexec で展開
            $foundMsi = Get-ChildItem -Path $tempMcExtract -Filter "*.msi" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundMsi) {
                Write-Host "  インストーラー (MSI) を展開中..." -ForegroundColor Yellow
                if (Test-Path $tempMsiExtract) { Remove-Item $tempMsiExtract -Recurse -Force }
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/a `"$($foundMsi.FullName)`" /qn TARGETDIR=`"$tempMsiExtract`"" -Wait -NoNewWindow
                $foundExe = Get-ChildItem -Path $tempMsiExtract -Filter "RICOH THETA Movie Converter.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            else {
                $foundExe = Get-ChildItem -Path $tempMcExtract -Filter "RICOH THETA Movie Converter.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            }

            if ($foundExe) {
                $srcFolder = $foundExe.DirectoryName
                if (Test-Path $movieConverterDir) { Remove-Item $movieConverterDir -Recurse -Force }
                Copy-Item -Path $srcFolder -Destination $movieConverterDir -Recurse -Force
                Write-Host "  RICOH THETA Movie Converter のセットアップが完了しました。" -ForegroundColor Green
            }
            else {
                Write-Error "RICOH THETA Movie Converter の実行ファイルが見つかりませんでした。"
            }
        }
        catch {
            Write-Error "Movie Converter の展開に失敗しました: $_"
        }
        finally {
            if (Test-Path $tempMcExtract) { Remove-Item $tempMcExtract -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $tempMsiExtract) { Remove-Item $tempMsiExtract -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
else {
    Write-Host "`n[2/3] RICOH THETA Movie Converter は既にセットアップ済みです。" -ForegroundColor Green
}

# 3. Setup Google SpatialMedia Tools
$smPy = Join-Path $spatialMediaDir "metadata_utils.py"
if (-not (Test-Path $smPy) -or $Force) {
    Write-Host "`n[3/3] Google 公式 SpatialMedia メタデータツールを取得中..." -ForegroundColor Yellow
    $smZipUrl = "https://github.com/google/spatial-media/archive/refs/heads/master.zip"
    $tempSmZip = Join-Path ([System.IO.Path]::GetTempPath()) "spatial_media_master.zip"
    $tempSmExtract = Join-Path ([System.IO.Path]::GetTempPath()) "spatial_media_extract"

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
    }
    catch {
        Write-Error "SpatialMedia のダウンロードまたは展開に失敗しました: $_"
    }
    finally {
        Remove-Item $tempSmZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tempSmExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host "`n[3/3] Google SpatialMedia ツールは既にセットアップ済みです。" -ForegroundColor Green
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "すべてのツールのセットアップが正常に完了しました！" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
