# 每日病程记录：先做一次真实采集，再记录（避免把旧 findings 当新样本）
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $root 'engine\winmedic.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $engine probe --set storage | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File $engine trend --record --set storage | Out-Null
exit $LASTEXITCODE