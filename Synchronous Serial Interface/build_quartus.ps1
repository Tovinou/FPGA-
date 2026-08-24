param(
    [string]$Project = "SSI",
    [string]$Revision = "SSI",
    [string]$QuartusBin,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Resolve-QuartusSh {
    param([string]$QuartusBin)

    if ($QuartusBin) {
        $candidate = Join-Path $QuartusBin "quartus_sh.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
        throw "quartus_sh.exe not found in QuartusBin: $QuartusBin"
    }

    $cmd = Get-Command "quartus_sh.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Path
    }

    $roots = @(
        "C:\intelFPGA_lite\25.1",
        "C:\intelFPGA_lite\25.1std",
        "C:\intelFPGA_lite",
        "C:\intelFPGA",
        "C:\altera",
        "C:\altera_lite"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $matches = Get-ChildItem -Path $root -Recurse -Filter "quartus_sh.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\quartus\\bin(64)?\\quartus_sh\.exe$" } |
            Sort-Object FullName -Descending
        if ($matches -and $matches.Count -gt 0) {
            return $matches[0].FullName
        }
    }

    throw "quartus_sh.exe not found. Install Quartus or provide -QuartusBin <...\\quartus\\bin64>."
}

function Invoke-QuartusBuild {
    param(
        [string]$QuartusSh,
        [string]$Project,
        [string]$Revision
    )

    if (-not (Test-Path "$Project.qpf")) {
        throw "Project file not found: $Project.qpf"
    }

    & $QuartusSh --flow compile $Project -c $Revision
    if ($LASTEXITCODE -ne 0) {
        throw "Quartus compile failed with exit code $LASTEXITCODE"
    }

    $sof = Join-Path (Join-Path $PSScriptRoot "output_files") "$Revision.sof"
    if (Test-Path $sof) {
        Write-Host "SOF generated: $sof"
    } else {
        Write-Host "Compile finished, but SOF not found at expected path: $sof"
    }
}

if ($Clean) {
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue (Join-Path $PSScriptRoot "output_files")
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue (Join-Path $PSScriptRoot "db")
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue (Join-Path $PSScriptRoot "incremental_db")
}

$quartusSh = Resolve-QuartusSh -QuartusBin $QuartusBin
Invoke-QuartusBuild -QuartusSh $quartusSh -Project $Project -Revision $Revision
