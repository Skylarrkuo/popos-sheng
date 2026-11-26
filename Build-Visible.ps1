[CmdletBinding()]
param([ValidateSet('Kernel','Configure','Rootfs','All')][string]$Stage = 'All')

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
$Host.UI.RawUI.WindowTitle = 'Pop!_OS 26.04 COSMIC for Xiaomi Pad 6S Pro'
$wslRepo = (& wsl.exe -d Ubuntu-24.04 -u root -- wslpath -a ($PSScriptRoot -replace '\\', '/')).Trim()
if ($LASTEXITCODE -ne 0 -or -not $wslRepo) { throw 'Unable to resolve the project in WSL' }

function Invoke-LinuxBuild([string]$Name, [string[]]$Arguments = @()) {
    & wsl.exe -d Ubuntu-24.04 -u root -- bash "$wslRepo/scripts/$Name" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name exited with code $LASTEXITCODE" }
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
