# Advanced Stress Tests for Channels & Messenger
$testsPassed = 0
$testsFailed = 0

function Assert-Condition($name, $condition, $details = "") {
    if ($condition) {
        Write-Host "[PASS] $name" -ForegroundColor Green
        $global:testsPassed++
    } else {
        Write-Host "[FAIL] $name - $details" -ForegroundColor Red
        $global:testsFailed++
    }
}

Write-Host "=== SUITE 5: Adversarial Tag Injections ===" -ForegroundColor Cyan

function Sanitize-Tag($rawTag) {
    if ([string]::IsNullOrWhiteSpace($rawTag)) { return "" }
    $clean = $rawTag.Trim().ToLower()
    while ($clean.StartsWith("@")) {
        $clean = $clean.Substring(1)
    }
    $filtered = -join ($clean.ToCharArray() | Where-Object { [char]::IsLetterOrDigit($_) -or $_ -eq '_' })
    return $filtered
}

function Validate-Tag($tag) {
    $clean = Sanitize-Tag $tag
    if ($clean.Length -lt 3) {
        return @{ IsValid = $false; Message = "Min 3 chars required" }
    }
    if ($clean.Length -gt 30) {
        return @{ IsValid = $false; Message = "Max 30 chars allowed" }
    }
    if ($clean -notmatch '^[a-z0-9_]{3,30}$') {
        return @{ IsValid = $false; Message = "Only latin letters, digits, underscore allowed" }
    }
    $reserved = @("sloosh", "admin", "support", "official", "channel", "user", "help")
    if ($reserved -contains $clean) {
        return @{ IsValid = $false; Message = "Reserved tag" }
    }
    return @{ IsValid = $true; Message = "Valid tag" }
}

# Path traversal attack
$traversal = "../../etc/passwd"
Assert-Condition "Path traversal sanitized" ((Sanitize-Tag $traversal) -eq "etcpasswd")
Assert-Condition "Path traversal validation result" ((Validate-Tag $traversal).IsValid -eq $true)

# URL query / fragment injection
$urlInjection = "channel_tag?auth=malicious#token"
Assert-Condition "URL injection sanitized" ((Sanitize-Tag $urlInjection) -eq "channel_tagauthmalicioustoken")

# SQL injection quote attempt
$sqlInjection = "' OR 1=1; --"
Assert-Condition "SQL injection sanitized" ((Sanitize-Tag $sqlInjection) -eq "or11")
Assert-Condition "SQL injection validation" ((Validate-Tag $sqlInjection).IsValid -eq $true)

# Symbols stripped to empty
$symbolsTag = "???---$$$///"
Assert-Condition "Symbols tag sanitized to empty" ((Sanitize-Tag $symbolsTag) -eq "")
Assert-Condition "Symbols tag fails validation" ((Validate-Tag $symbolsTag).IsValid -eq $false)

# Reserved words case insensitivity
Assert-Condition "SLOOSH uppercase rejected" ((Validate-Tag "SLOOSH").IsValid -eq $false)
Assert-Condition "sLoOsH mixed rejected" ((Validate-Tag "sLoOsH").IsValid -eq $false)
Assert-Condition "ADMIN rejected" ((Validate-Tag "ADMIN").IsValid -eq $false)
Assert-Condition "Support rejected" ((Validate-Tag "Support").IsValid -eq $false)

Write-Host "=== SUITE 6: Subscriber Count Declension Cases ===" -ForegroundColor Cyan

function Format-Subscribers($count) {
    $c = [Math]::Max(0, $count)
    $mod10 = $c % 10
    $mod100 = $c % 100
    if ($mod10 -eq 1 -and $mod100 -ne 11) {
        return "$c suffix_1"
    } elseif ($mod10 -ge 2 -and $mod10 -le 4 -and ($mod100 -lt 12 -or $mod100 -gt 14)) {
        return "$c suffix_2_4"
    } else {
        return "$c suffix_5_plus"
    }
}

$cases = @(
    @{ Count = 0; Expected = "0 suffix_5_plus" },
    @{ Count = 1; Expected = "1 suffix_1" },
    @{ Count = 2; Expected = "2 suffix_2_4" },
    @{ Count = 4; Expected = "4 suffix_2_4" },
    @{ Count = 5; Expected = "5 suffix_5_plus" },
    @{ Count = 10; Expected = "10 suffix_5_plus" },
    @{ Count = 11; Expected = "11 suffix_5_plus" },
    @{ Count = 12; Expected = "12 suffix_5_plus" },
    @{ Count = 14; Expected = "14 suffix_5_plus" },
    @{ Count = 21; Expected = "21 suffix_1" },
    @{ Count = 22; Expected = "22 suffix_2_4" },
    @{ Count = 25; Expected = "25 suffix_5_plus" },
    @{ Count = 101; Expected = "101 suffix_1" },
    @{ Count = 111; Expected = "111 suffix_5_plus" },
    @{ Count = 112; Expected = "112 suffix_5_plus" },
    @{ Count = 124; Expected = "124 suffix_2_4" },
    @{ Count = 1000; Expected = "1000 suffix_5_plus" }
)

foreach ($tc in $cases) {
    $actual = Format-Subscribers $tc.Count
    Assert-Condition "Pluralization for $($tc.Count)" ($actual -eq $tc.Expected) "Got '$actual', expected '$($tc.Expected)'"
}

Write-Host "=== SUMMARY ===" -ForegroundColor Yellow
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor Red

if ($testsFailed -gt 0) {
    exit 1
}
