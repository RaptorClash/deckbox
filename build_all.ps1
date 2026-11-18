#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Compiles DeckBox for Windows (.exe) and Android (.apk).
.EXAMPLE
    .\build_all.ps1
    .\build_all.ps1 --target both
    .\build_all.ps1 --platforms android
#>
$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DeckBox One-Click Build (Windows + Android)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

& python "$PSScriptRoot\tool\build_target.py" --root "$PSScriptRoot" --build-all @args
exit $LASTEXITCODE
