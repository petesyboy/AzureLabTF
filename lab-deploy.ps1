<#
.SYNOPSIS
    Automated deployment and configuration wrapper for Azure Lab 6.12.
    Executes Terraform workflow, runs the Python configuration script,
    and times the total elapsed time of the run.
#>

$ErrorActionPreference = "Stop"

$StartTime = Get-Date

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " Starting Azure Lab Deployment" -ForegroundColor Cyan
Write-Host " Start Time: $StartTime" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

try {
    Write-Host "`n>>> 1/5: Running terraform init..." -ForegroundColor Yellow
    terraform init
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed with exit code $LASTEXITCODE" }

    Write-Host "`n>>> 2/5: Running terraform plan..." -ForegroundColor Yellow
    terraform plan -out=tfplan
    if ($LASTEXITCODE -ne 0) { throw "terraform plan failed with exit code $LASTEXITCODE" }

    Write-Host "`n>>> 3/5: Running terraform apply..." -ForegroundColor Yellow
    terraform apply tfplan
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed with exit code $LASTEXITCODE" }

    Write-Host "`n>>> 4/5: Setting up Python virtual environment..." -ForegroundColor Yellow
    $VenvPath = ".\scripts\.venv"
    if (-not (Test-Path $VenvPath)) {
        python -m venv $VenvPath
    }

    Write-Host "Installing requirements..."
    & "$VenvPath\Scripts\pip.exe" install -r .\scripts\requirements.txt
    if ($LASTEXITCODE -ne 0) { throw "pip install failed with exit code $LASTEXITCODE" }

    Write-Host "`n>>> 5/5: Running configure_lab.py..." -ForegroundColor Yellow
    if (-not (Test-Path ".\scripts\configure_lab.py")) {
        throw ".\scripts\configure_lab.py was not found. Has terraform generated it?"
    }
    
    # Run the configuration script
    & "$VenvPath\Scripts\python.exe" .\scripts\configure_lab.py
    if ($LASTEXITCODE -ne 0) { throw "configure_lab.py failed with exit code $LASTEXITCODE" }

    $Success = $true
} catch {
    Write-Error "Deployment failed: $_"
    $Success = $false
}

$EndTime = Get-Date
$Elapsed = $EndTime - $StartTime

Write-Host "`n=======================================================" -ForegroundColor Cyan
if ($Success) {
    Write-Host " Lab Deployment Completed SUCCESSFULLY!" -ForegroundColor Green
} else {
    Write-Host " Lab Deployment FAILED!" -ForegroundColor Red
}
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " Start Time:         $StartTime"  
Write-Host " End Time:           $EndTime"
Write-Host (" Total Elapsed Time: {0:D2}h {1:D2}m {2:D2}s" -f $Elapsed.Hours, $Elapsed.Minutes, $Elapsed.Seconds)
Write-Host "=======================================================" -ForegroundColor Cyan

if (-not $Success) {
    exit 1
}
