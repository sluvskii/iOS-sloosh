# PowerShell Edge Case & Stress Testing Harness for Milestone 2

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RUNNING ADVERSARIAL STRESS-TESTS & EDGE-CASE EVALUATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$stressFailures = New-Object System.Collections.ArrayList
$stressPasses = New-Object System.Collections.ArrayList

function Assert-Stress($name, $condition, $failMsg = "") {
    if ($condition) {
        Write-Host " [PASS] $name" -ForegroundColor Green
        [void]$stressPasses.Add($name)
    } else {
        Write-Host " [FAIL] $name - $failMsg" -ForegroundColor Red
        [void]$stressFailures.Add("$name - $failMsg")
    }
}

# 1. Stress Test: Russian Subscriber Count Grammar Engine
function Format-Subscribers($count) {
    $c = [Math]::Max(0, $count)
    $mod10 = $c % 10
    $mod100 = $c % 100
    if ($mod10 -eq 1 -and $mod100 -ne 11) {
        return "$c подписчик"
    } elseif ($mod10 -ge 2 -and $mod10 -le 4 -and -not ($mod100 -ge 12 -and $mod100 -le 14)) {
        return "$c подписчика"
    } else {
        return "$c подписчиков"
    }
}

Assert-Stress "Grammar: 0 подписчиков" ((Format-Subscribers 0) -eq "0 подписчиков")
Assert-Stress "Grammar: 1 подписчик" ((Format-Subscribers 1) -eq "1 подписчик")
Assert-Stress "Grammar: 2 подписчика" ((Format-Subscribers 2) -eq "2 подписчика")
Assert-Stress "Grammar: 4 подписчика" ((Format-Subscribers 4) -eq "4 подписчика")
Assert-Stress "Grammar: 5 подписчиков" ((Format-Subscribers 5) -eq "5 подписчиков")
Assert-Stress "Grammar: 11 подписчиков (exception to 1)" ((Format-Subscribers 11) -eq "11 подписчиков")
Assert-Stress "Grammar: 12 подписчиков (exception to 2)" ((Format-Subscribers 12) -eq "12 подписчиков")
Assert-Stress "Grammar: 14 подписчиков (exception to 4)" ((Format-Subscribers 14) -eq "14 подписчиков")
Assert-Stress "Grammar: 21 подписчик" ((Format-Subscribers 21) -eq "21 подписчик")
Assert-Stress "Grammar: 22 подписчика" ((Format-Subscribers 22) -eq "22 подписчика")
Assert-Stress "Grammar: 104 подписчика" ((Format-Subscribers 104) -eq "104 подписчика")
Assert-Stress "Grammar: 111 подписчиков" ((Format-Subscribers 111) -eq "111 подписчиков")

# 2. Stress Test: Channel Input Trimming & Validation
function Test-FormValid($name, $isCreating) {
    $trimmed = $name.Trim()
    return (-not [string]::IsNullOrEmpty($trimmed)) -and (-not $isCreating)
}

Assert-Stress "Validation: Empty name is invalid" (-not (Test-FormValid "" $false))
Assert-Stress "Validation: Whitespace-only name '   \t\n  ' is invalid" (-not (Test-FormValid "   `t`n  " $false))
Assert-Stress "Validation: Valid name with spaces is valid" (Test-FormValid "  Киноман 2026  " $false)
Assert-Stress "Validation: isCreating=true disables form" (-not (Test-FormValid "Valid Name" $true))

# 3. Stress Test: Fallback Timestamps and Previews
function Get-ChannelLastActivity($lastPostTs, $updatedAt) {
    if ($lastPostTs -ne $null) { return $lastPostTs }
    return $updatedAt
}

Assert-Stress "Fallback: Uses lastPostTimestampMs if available" ((Get-ChannelLastActivity 5000 2000) -eq 5000)
Assert-Stress "Fallback: Uses updatedAtMs if lastPostTimestampMs is null" ((Get-ChannelLastActivity $null 2000) -eq 2000)

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " STRESS-TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Stress Tests Passed: $($stressPasses.Count)" -ForegroundColor Green
Write-Host "Total Stress Tests Failed: $($stressFailures.Count)" -ForegroundColor Red

if ($stressFailures.Count -gt 0) {
    exit 1
} else {
    exit 0
}
