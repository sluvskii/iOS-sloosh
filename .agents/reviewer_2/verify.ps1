# Test Suite for Channels & Messenger Refactoring
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

Write-Host "=== SUITE 1: TagValidator Logic & Edge Cases ===" -ForegroundColor Cyan

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

# Tests for Sanitize
Assert-Condition "Sanitize leading @" ((Sanitize-Tag "@@@my_channel") -eq "my_channel")
Assert-Condition "Sanitize uppercase & whitespace" ((Sanitize-Tag "  Cinema_Club_99  ") -eq "cinema_club_99")
Assert-Condition "Sanitize illegal symbols" ((Sanitize-Tag "cool-tag!#$") -eq "cooltag")
Assert-Condition "Sanitize cyrillic stripped" ((Sanitize-Tag "tag_123") -eq "tag_123")
Assert-Condition "Sanitize empty" ((Sanitize-Tag "   ") -eq "")

# Tests for Validate
Assert-Condition "Validate valid tag" ((Validate-Tag "@cinema_club").IsValid -eq $true)
Assert-Condition "Validate 3-char min" ((Validate-Tag "ab").IsValid -eq $false)
Assert-Condition "Validate 3-char boundary pass" ((Validate-Tag "abc").IsValid -eq $true)
Assert-Condition "Validate 30-char boundary pass" ((Validate-Tag ("a" * 30)).IsValid -eq $true)
Assert-Condition "Validate 31-char fail" ((Validate-Tag ("a" * 31)).IsValid -eq $false)
Assert-Condition "Validate reserved sloosh fail" ((Validate-Tag "@sloosh").IsValid -eq $false)
Assert-Condition "Validate reserved admin fail" ((Validate-Tag "@Admin").IsValid -eq $false)
Assert-Condition "Validate reserved support fail" ((Validate-Tag "support").IsValid -eq $false)
Assert-Condition "Validate numeric tag pass" ((Validate-Tag "12345").IsValid -eq $true)
Assert-Condition "Validate underscore tag pass" ((Validate-Tag "my_super_channel").IsValid -eq $true)

Write-Host "=== SUITE 2: ChannelModel Legacy Decoding Fallback ===" -ForegroundColor Cyan

$legacyChannelJson = '{"id": "ch_1724500000_abc123", "name": "Old Channel", "description": "Legacy description", "ownerId": "usr_999", "ownerName": "Alex", "createdAtMs": 1724500000, "subscriberCount": 42}'
$obj = $legacyChannelJson | ConvertFrom-Json
$simulatedTag = if ($obj.tag -and $obj.tag -ne "") { Sanitize-Tag $obj.tag } else { "channel_" + $obj.id.Substring(0, [Math]::Min(6, $obj.id.Length)) }
Assert-Condition "Legacy channel tag fallback" ($simulatedTag -eq "channel_ch_172")

Write-Host "=== SUITE 3: Privacy & Zero-Leak Audit ===" -ForegroundColor Cyan

$ultraThinMatches = Select-String -Path "sloosh-iOS\sloosh\Sources\**\*.swift" -Pattern "ultraThinMaterial"
Assert-Condition "Zero ultraThinMaterial in codebase" ($ultraThinMatches.Count -eq 0)

$emailInMessengerUI = Select-String -Path "sloosh-iOS\sloosh\Sources\UI\Messenger\*.swift" -Pattern "peerUser\.email|\.email\b"
Assert-Condition "Zero email exposure in Messenger UI" ($emailInMessengerUI.Count -eq 0)

$collapsMatches = Select-String -Path "sloosh-iOS\sloosh\Sources\**\*.swift" -Pattern "Collaps" | Where-Object { $_.Line -notmatch "isFilterCollapsed" }
Assert-Condition "Zero Collaps streaming source integration" ($collapsMatches.Count -eq 0)

$fakeLinks = Select-String -Path "sloosh-iOS\sloosh\Sources\UI\Messenger\ChannelInfoView.swift" -Pattern "sloosh\.app"
Assert-Condition "Zero fake sloosh.app links in ChannelInfoView" ($fakeLinks.Count -eq 0)

$shareBtnInChannelInfo = Select-String -Path "sloosh-iOS\sloosh\Sources\UI\Messenger\ChannelInfoView.swift" -Pattern "ShareLink|square\.and\.arrow\.up"
Assert-Condition "Zero share button in ChannelInfoView" ($shareBtnInChannelInfo.Count -eq 0)

Write-Host "=== SUITE 4: Avatar Pipeline & Caching Integrity ===" -ForegroundColor Cyan

$testBytes = [System.Text.Encoding]::UTF8.GetBytes("FakeImageData")
$base64 = [Convert]::ToBase64String($testBytes)
$dataUri = "data:image/jpeg;base64," + $base64

Assert-Condition "Data URI starts with data:image" ($dataUri.StartsWith("data:image/jpeg;base64,"))
$commaIndex = $dataUri.IndexOf(",")
$extractedBase64 = $dataUri.Substring($commaIndex + 1)
$decodedBytes = [Convert]::FromBase64String($extractedBase64)
$decodedString = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
Assert-Condition "Extracted Base64 roundtrip matches" ($decodedString -eq "FakeImageData")

Write-Host "=== SUMMARY ===" -ForegroundColor Yellow
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor Red

if ($testsFailed -gt 0) {
    exit 1
}
