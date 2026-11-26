[CmdletBinding()]
param(
    [ValidateSet('Kernel','Configure','Rootfs','All')][string]$Stage = 'All',
    [string]$CosmicDeb,
    [string]$CosmicDebSha256
)

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
$Host.UI.RawUI.WindowTitle = 'Pop!_OS 26.04 COSMIC for Xiaomi Pad 6S Pro'
$wslRepo = (& wsl.exe -d Ubuntu-24.04 -u root -- wslpath -a ($PSScriptRoot -replace '\\', '/')).Trim()
if ($LASTEXITCODE -ne 0 -or -not $wslRepo) { throw 'Unable to resolve the project in WSL' }

function Invoke-LinuxBuild([string]$Name, [string[]]$Arguments = @(), [string[]]$Environment = @()) {
    & wsl.exe -d Ubuntu-24.04 -u root -- env @Environment bash "$wslRepo/scripts/$Name" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name exited with code $LASTEXITCODE" }
}

if ($Stage -in @('Configure','Rootfs','All')) {
    $settingsEnv = @()
    if ($CosmicDeb) {
        $debPath = (Resolve-Path -LiteralPath $CosmicDeb).Path
        $wslDeb = (& wsl.exe -d Ubuntu-24.04 -u root -- wslpath -a ($debPath -replace '\\', '/')).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $wslDeb) { throw 'Unable to resolve the COSMIC Settings package in WSL' }
        $settingsEnv += "SHENG_POP_COSMIC_DEB=$wslDeb"
        if ($CosmicDebSha256) { $settingsEnv += "SHENG_POP_COSMIC_DEB_SHA256=$CosmicDebSha256" }
    }
    Invoke-LinuxBuild 'build-cosmic-settings.sh' -Environment $settingsEnv
}
if ($Stage -in @('Kernel','All')) { Invoke-LinuxBuild 'build-kernel.sh' }
if ($Stage -in @('Configure','Rootfs','All')) {
    Invoke-LinuxBuild 'prepare-rootfs.sh'
    Invoke-LinuxBuild 'build-device-packages.sh'
    if ($Stage -eq 'Configure') {
        Invoke-LinuxBuild 'build-image.sh' @('--configure-only')
    } else {
        Invoke-LinuxBuild 'build-image.sh'
        Invoke-LinuxBuild 'publish-local-apt.sh'
    }
}
