<#
.SYNOPSIS
    RICOH公式インストーラーから必要な変換エンジン・バイナリのみを自動抽出してセットアップします。

.DESCRIPTION
    RICOH THETA PC基本アプリのインストーラー (RICOH THETA Setup.exe) および
    RICOH THETA Movie Converter のインストーラー (RICOH_THETA_Movie_Converter_ja.zip) から、
    動画変換・天頂補正スティッチ・4ch空間音声展開に必要なバイナリファイルのみを自動抽出し、
    ローカルの tools/ フォルダ配下にポータブル環境として構築します。
    公式インストーラーは著作権・ライセンス保護のため本リポジトリには含まれていませんが、
    本スクリプトを実行することで安全にスタンドアロン変換環境を構築できます。

.PARAMETER ThetaSetupPath
    RICOH THETA PC基本アプリのインストーラーパス (RICOH THETA Setup.exe)。
    省略時はカレントディレクトリおよび Downloads フォルダから自動検出します。

.PARAMETER MovieConverterZipPath
    RICOH THETA Movie Converter の zip / msi パス (RICOH_THETA_Movie_Converter_ja.zip)。
    省略時はカレントディレクトリおよび Downloads フォルダから自動検出します。

.PARAMETER Help
    ヘルプ情報を表示します (-h または --help)。

.EXAMPLE
    .\Setup-ThetaTools.ps1

.EXAMPLE
    .\Setup-ThetaTools.ps1 -ThetaSetupPath .\RICOH_THETA_Setup.exe -MovieConverterZipPath .\RICOH_THETA_Movie_Converter_ja.zip

.EXAMPLE
    .\Setup-ThetaTools.ps1 -h
#>
[CmdletBinding(DefaultParameterSetName = 'Setup')]
param (
    #region Parameters
    [Parameter(ParameterSetName = 'Help')]
    [Alias('h', '-help')]
    [switch]$Help,

    [Parameter(ParameterSetName = 'Setup')]
    [string]$ThetaSetupPath,

    [Parameter(ParameterSetName = 'Setup')]
    [string]$MovieConverterZipPath
    #endregion
)

#region Help Handling
if ($Help -or ($PSCmdlet.ParameterSetName -eq 'Help')) {
    Get-Help -Name $PSCommandPath -Full
    exit 0
}
#endregion

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "     RICOH THETA 変換エンジン自動セットアップツール         " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $PSCommandPath
$toolsDir = Join-Path $scriptDir "tools"
$dualfishDir = Join-Path $toolsDir "dualfishblender"
$movieConverterDir = Join-Path $toolsDir "ricoh_movie_converter"

if (-not (Test-Path $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null }
if (-not (Test-Path $dualfishDir)) { New-Item -ItemType Directory -Path $dualfishDir -Force | Out-Null }
if (-not (Test-Path $movieConverterDir)) { New-Item -ItemType Directory -Path $movieConverterDir -Force | Out-Null }

#region 1. Setup DualfishBlender (THETA App Stitch Engine)
Write-Host "`n[1/2] 映像スティッチエンジン (DualfishBlender) のセットアップ..." -ForegroundColor Yellow

$appDataBlender = Join-Path $env:LOCALAPPDATA "Programs\RicohTheta\resources\tools\dualfishblender\win"
$dualfishDone = $false

# Search installer if not specified
if ([string]::IsNullOrWhiteSpace($ThetaSetupPath)) {
    $searchPaths = @(
        $scriptDir,
        ($env:USERPROFILE + "\Downloads"),
        ($env:USERPROFILE + "\Desktop")
    )
    foreach ($sp in $searchPaths) {
        $found = Get-ChildItem -Path $sp -Filter "*THETA*Setup*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $ThetaSetupPath = $found.FullName
            break
        }
    }
}

# Method A: Extract from Installer via 7z
if ($ThetaSetupPath -and (Test-Path $ThetaSetupPath)) {
    Write-Host "  インストーラーを検出: $ThetaSetupPath" -ForegroundColor Gray
    $7zCmd = Get-Command 7z, 7za -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($7zCmd) {
        $tempRoot = [System.IO.Path]::GetTempPath()
        $tempExtract = Join-Path $tempRoot ("theta_setup_" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
        try {
            Write-Host "  バイナリを抽出中..." -ForegroundColor Gray
            & $7zCmd.Source e "$ThetaSetupPath" "`$PLUGINSDIR\app-64.7z" -o"$tempExtract" -y *>$null
            if (Test-Path "$tempExtract\app-64.7z") {
                & $7zCmd.Source x "$tempExtract\app-64.7z" "resources\tools\dualfishblender\win\*" -o"$tempExtract\out" -y *>$null
                $extractedWin = Join-Path $tempExtract "out\resources\tools\dualfishblender\win"
                if (Test-Path (Join-Path $extractedWin "DualfishBlender.exe")) {
                    Copy-Item "$extractedWin\*" -Destination $dualfishDir -Recurse -Force
                    $dualfishDone = $true
                    Write-Host "  [OK] DualfishBlender の抽出・配置に成功しました。" -ForegroundColor Green
                }
            }
        } finally {
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Method B: Fallback from already installed AppData
if (-not $dualfishDone -and (Test-Path (Join-Path $appDataBlender "DualfishBlender.exe"))) {
    Write-Host "  既存のインストール環境からコピー中: $appDataBlender" -ForegroundColor Gray
    Copy-Item "$appDataBlender\*" -Destination $dualfishDir -Recurse -Force
    $dualfishDone = $true
    Write-Host "  [OK] インストール環境からのコピーに成功しました。" -ForegroundColor Green
}

if (-not $dualfishDone) {
    Write-Warning "  [WARN] DualfishBlender の取得に失敗しました。RICOH THETA Setup.exe を配置するか、RICOH THETA アプリをインストールしてください。"
}
#endregion

#region 2. Setup RICOH THETA Movie Converter (Spatial Audio Engine)
Write-Host "`n[2/2] 4ch 空間音声エンジン (RICOH THETA Movie Converter) のセットアップ..." -ForegroundColor Yellow

$mcDone = $false

# Search movie converter archive if not specified
if ([string]::IsNullOrWhiteSpace($MovieConverterZipPath)) {
    $searchPaths = @(
        $scriptDir,
        ($env:USERPROFILE + "\Downloads"),
        ($env:USERPROFILE + "\Desktop")
    )
    foreach ($sp in $searchPaths) {
        $found = Get-ChildItem -Path $sp -Filter "*Movie_Converter*.zip" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $MovieConverterZipPath = $found.FullName
            break
        }
        $foundMsi = Get-ChildItem -Path $sp -Filter "*Installer*.msi" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundMsi) {
            $MovieConverterZipPath = $foundMsi.FullName
            break
        }
    }
}

if ($MovieConverterZipPath -and (Test-Path $MovieConverterZipPath)) {
    Write-Host "  インストーラーを検出: $MovieConverterZipPath" -ForegroundColor Gray
    $tempRoot = [System.IO.Path]::GetTempPath()
    $tempMc = Join-Path $tempRoot ("theta_mc_" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempMc -Force | Out-Null
    try {
        $msiFile = $null
        if ($MovieConverterZipPath.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "  Zip を展開中..." -ForegroundColor Gray
            Expand-Archive -Path $MovieConverterZipPath -DestinationPath $tempMc -Force
            $msiFile = (Get-ChildItem -Path $tempMc -Filter "*.msi" -Recurse | Select-Object -First 1).FullName
        } elseif ($MovieConverterZipPath.EndsWith(".msi", [System.StringComparison]::OrdinalIgnoreCase)) {
            $msiFile = $MovieConverterZipPath
        }

        if ($msiFile -and (Test-Path $msiFile)) {
            Write-Host "  MSI から必要ファイルを抽出中..." -ForegroundColor Gray
            $adminOut = Join-Path $tempMc "admin_out"
            New-Item -ItemType Directory -Path $adminOut -Force | Out-Null
            $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/a `"$msiFile`" /qn TARGETDIR=`"$adminOut`"" -Wait -PassThru
            
            $sourceBin = (Get-ChildItem -Path $adminOut -Filter "RICOH THETA Movie Converter.exe" -Recurse | Select-Object -First 1).DirectoryName
            if ($sourceBin -and (Test-Path (Join-Path $sourceBin "RICOH THETA Movie Converter.exe"))) {
                Copy-Item "$sourceBin\*" -Destination $movieConverterDir -Recurse -Force
                $mcDone = $true
                Write-Host "  [OK] Movie Converter ランタイムの抽出・配置に成功しました。" -ForegroundColor Green
            }
        }
    } finally {
        Remove-Item $tempMc -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $mcDone -and (Test-Path (Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe"))) {
    $mcDone = $true
    Write-Host "  [OK] 既存の Movie Converter ランタイムを確認しました。" -ForegroundColor Green
}

if (-not $mcDone) {
    Write-Warning "  [WARN] RICOH THETA Movie Converter の取得に失敗しました。RICOH_THETA_Movie_Converter_ja.zip を配置してください。"
}
#endregion

#region Summary & Verification
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "セットアップ完了確認:" -ForegroundColor Cyan
Write-Host "  - 映像スティッチエンジン : $(if (Test-Path (Join-Path $dualfishDir "DualfishBlender.exe")) { '[OK] 利用可能' } else { '[NG] 未設定' })" -ForegroundColor $(if (Test-Path (Join-Path $dualfishDir "DualfishBlender.exe")) { 'Green' } else { 'Red' })
Write-Host "  - 4ch 空間音声エンジン   : $(if (Test-Path (Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe")) { '[OK] 利用可能' } else { '[NG] 未設定' })" -ForegroundColor $(if (Test-Path (Join-Path $movieConverterDir "RICOH THETA Movie Converter.exe")) { 'Green' } else { 'Red' })
Write-Host "============================================================" -ForegroundColor Cyan
