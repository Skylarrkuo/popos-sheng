[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$inputDir = Join-Path $PSScriptRoot 'inputs'
$deviceDir = Join-Path $inputDir 'debs'
New-Item -ItemType Directory -Path $inputDir,$deviceDir -Force | Out-Null

$downloads = @(foreach ($source in (Import-Csv -Delimiter "`t" (Join-Path $PSScriptRoot 'sources.tsv'))) {
    if ($source.input.EndsWith('.iso')) {
        $iso = Join-Path (Split-Path -Parent $PSScriptRoot) $source.input
        if ((Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash -ine $source.sha256) {
            throw "Official ISO does not match the tracked SHA-256: $iso"
        }
        continue
    }
    $parts = ([uri]$source.source).AbsolutePath.Trim('/').Split('/')
    @{
        Url = "https://github.com/$($parts[0])/$($parts[1])/archive/$($source.revision).tar.gz"
        Path = Join-Path $inputDir $source.input
        Hash = $source.sha256
    }
})
$downloads += @(foreach ($source in (Import-Csv -Delimiter "`t" (Join-Path $PSScriptRoot 'device-sources.tsv'))) {
    @{ Url = $source.url; Path = Join-Path $deviceDir $source.asset; Hash = $source.sha256 }
})

$downloads | ForEach-Object -Parallel {
    $ErrorActionPreference = 'Stop'
    $item = $_
    $name = Split-Path -Leaf $item.Path
    if ((Test-Path -LiteralPath $item.Path -PathType Leaf) -and
        ((Get-FileHash -Algorithm SHA256 -LiteralPath $item.Path).Hash -ieq $item.Hash)) {
        "Verified $name"
        return
    }
    "Downloading $name"
    $partial = "$($item.Path).partial"
    Invoke-WebRequest -Uri $item.Url -OutFile $partial -ConnectionTimeoutSeconds 20 -OperationTimeoutSeconds 300 -MaximumRetryCount 1
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $partial).Hash -ine $item.Hash) {
        throw "SHA-256 mismatch for $name"
    }
    Move-Item -LiteralPath $partial -Destination $item.Path -Force
    "Verified $name"
} -ThrottleLimit 5
