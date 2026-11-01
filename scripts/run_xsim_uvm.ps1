$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

foreach ($tool in @('xvlog', 'xelab', 'xsim')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not on PATH. Open the Vivado 2026.1 command prompt and retry."
    }
}

New-Item -ItemType Directory -Force -Path 'build\xsim\uvm' | Out-Null
Push-Location 'build\xsim\uvm'
try {
    xvlog -sv -L uvm ..\..\..\rtl\rv32i_core.sv ..\..\..\tb\uvm\rv32i_uvm_if.sv ..\..\..\tb\uvm\rv32i_uvm_pkg.sv ..\..\..\tb\uvm\tb_uvm_random.sv
    if ($LASTEXITCODE -ne 0) { throw "xvlog UVM compile failed with exit code $LASTEXITCODE" }

    xelab -L uvm tb_uvm_random -s tb_uvm_random_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab UVM elaboration failed with exit code $LASTEXITCODE" }

    foreach ($seed in @(1, 17, 20261101)) {
        $waveform = "tb_uvm_random_seed_$seed.wdb"
        Write-Host "Running UVM regression with SystemVerilog seed $seed"
        $xsimOutput = & xsim tb_uvm_random_sim -sv_seed $seed -runall -wdb $waveform 2>&1
        $xsimExitCode = $LASTEXITCODE
        $xsimOutput | Tee-Object -FilePath "tb_uvm_random_seed_$seed.log"
        $xsimText = $xsimOutput -join [Environment]::NewLine
        if ($xsimExitCode -ne 0) { throw "xsim UVM seed $seed failed with exit code $xsimExitCode" }
        if ($xsimText -match '(?m)^\s*UVM_(ERROR|FATAL)(?!\s*:\s*0)\b|FAIL:') { throw "UVM seed $seed reported an error." }
        if ($xsimText -notmatch 'PASS: UVM reference scoreboard') { throw "UVM seed $seed PASS marker was not found." }
    }
}
finally {
    Pop-Location
}
