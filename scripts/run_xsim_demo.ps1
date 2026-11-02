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
    xvlog -sv ..\..\rtl\rv32i_core.sv ..\..\rtl\rv32i_demo_system.sv ..\..\tb\tb_rv32i_demo_system.sv
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }
    xelab tb_rv32i_demo_system -s tb_rv32i_demo_system_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }
    $output = & xsim tb_rv32i_demo_system_sim -runall 2>&1
    $exitCode = $LASTEXITCODE
    $output | Tee-Object -FilePath 'tb_rv32i_demo_system.log'
    $text = $output -join [Environment]::NewLine
    if ($exitCode -ne 0) { throw "xsim failed with exit code $exitCode" }
    if ($text -match 'FAIL:') { throw 'Demo system test printed a FAIL marker.' }
    if ($text -notmatch 'PASS: demo system;') { throw 'Demo system PASS marker not found.' }
}
finally { Pop-Location }
