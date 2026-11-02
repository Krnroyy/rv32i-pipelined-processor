$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

foreach ($tool in @('xvlog', 'xelab', 'xsim')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not on PATH. Open the Vivado 2026.1 command prompt and retry."
    }
}

New-Item -ItemType Directory -Force -Path 'build\xsim' | Out-Null
Push-Location 'build\xsim'
try {
    xvlog -sv ..\..\rtl\rv32i_core.sv ..\..\rtl\rv32i_demo_system.sv ..\..\tb\tb_core_smoke.sv ..\..\tb\tb_hazard_control.sv ..\..\tb\tb_rv32i_demo_system.sv
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }

    foreach ($testName in @('tb_core_smoke', 'tb_hazard_control', 'tb_rv32i_demo_system')) {
        $snapshot = "${testName}_sim"
        xelab $testName -s $snapshot
        if ($LASTEXITCODE -ne 0) { throw "xelab failed for $testName with exit code $LASTEXITCODE" }

        $xsimOutput = & xsim $snapshot -runall 2>&1
        $xsimExitCode = $LASTEXITCODE
        $xsimOutput | Tee-Object -FilePath "$testName.log"
        $xsimText = $xsimOutput -join [Environment]::NewLine
        if ($xsimExitCode -ne 0) { throw "xsim failed for $testName with exit code $xsimExitCode" }
        if ($xsimText -match 'FAIL:') { throw "$testName printed a FAIL marker." }
        if ($xsimText -notmatch 'PASS:') { throw "$testName PASS marker was not found." }
    }
}
finally {
    Pop-Location
}
