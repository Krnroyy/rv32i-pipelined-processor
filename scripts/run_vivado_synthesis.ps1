param(
    [string]$VivadoBin = 'C:\AMDDesignTools\2026.1\Vivado\bin',
    [string]$Part = 'xczu7ev-ffvc1156-2-e',
    [double]$ClockPeriodNs = 10.0,
    [string]$ReportDir = '.\reports\vivado'
)

$ErrorActionPreference = 'Stop'

$vivado = Get-Command vivado -ErrorAction SilentlyContinue
if ($vivado) {
    $vivadoExe = $vivado.Source
} else {
    $vivadoExe = Join-Path $VivadoBin 'vivado.bat'
    if (-not (Test-Path -LiteralPath $vivadoExe)) {
        throw "Vivado was not found on PATH or at '$vivadoExe'. Set -VivadoBin to your Vivado bin folder."
    }
}

if ($ClockPeriodNs -le 0) { throw 'ClockPeriodNs must be greater than zero.' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$tcl = Join-Path $PSScriptRoot 'run_vivado_synthesis.tcl'
if ([IO.Path]::IsPathRooted($ReportDir)) {
    $resolvedReportDir = [IO.Path]::GetFullPath($ReportDir)
} else {
    $resolvedReportDir = [IO.Path]::GetFullPath((Join-Path (Get-Location) $ReportDir))
}
New-Item -ItemType Directory -Path $resolvedReportDir -Force | Out-Null

& $vivadoExe -mode batch -source $tcl -tclargs $repoRoot $Part $ClockPeriodNs $resolvedReportDir
if ($LASTEXITCODE -ne 0) { throw "Vivado synthesis/report flow failed with exit code $LASTEXITCODE." }

Write-Host "PASS: Vivado synthesis and timing reports are in $resolvedReportDir"
