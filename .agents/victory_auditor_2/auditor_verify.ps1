# Independent Auditor Deep Verification Script
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  INDEPENDENT AUDITOR FORENSIC & RULES COMPLIANCE SUITE   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$passed = 0
$failed = 0

function Test-Assert($name, $condition, $details = "") {
    if ($condition) {
        Write-Host "[PASS] $name" -ForegroundColor Green
        $global:passed++
    } else {
        Write-Host "[FAIL] $name : $details" -ForegroundColor Red
        $global:failed++
    }
}

# 1. Check ultraThinMaterial
$ultraThin = Get-ChildItem -Path "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources" -Recurse -Filter "*.swift" | Select-String "ultraThinMaterial"
Test-Assert "Rule R4/Project: Zero ultraThinMaterial across entire codebase" ($ultraThin.Count -eq 0)

# 2. Check Collaps source leak
$collaps = Get-ChildItem -Path "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources" -Recurse -Filter "*.swift" | Select-String "Collaps" | Where-Object { $_.Line -notmatch "isFilterCollapsed" }
Test-Assert "Rule R4/Project: Zero Collaps provider in codebase" ($collaps.Count -eq 0)

# 3. Check ChannelInfoView (R3)
$channelInfoContent = Get-Content -Path "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\ChannelInfoView.swift" -Raw -Encoding UTF8
$hasEditButton = $channelInfoContent -match 'showEditSheet = true'
$hasFakeLink = $channelInfoContent -match 'sloosh\.app'
$hasShareButton = $channelInfoContent -match 'ShareLink|square\.and\.arrow\.up'
$hasDuplicateSettings = ($channelInfoContent | Select-String -Pattern 'gearshape' -AllMatches).Matches.Count

Test-Assert "Rule R3: ChannelInfoView has edit button triggering showEditSheet" $hasEditButton
Test-Assert "Rule R3: ChannelInfoView has zero fake sloosh.app links" (!$hasFakeLink)
Test-Assert "Rule R3: ChannelInfoView has zero share buttons" (!$hasShareButton)
Test-Assert "Rule R3: ChannelInfoView has zero duplicate gear buttons" ($hasDuplicateSettings -eq 0)

# 4. Check SlooshUser privacy encoding (R1/R4)
$modelsContent = Get-Content -Path "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Models\MessengerModels.swift" -Raw -Encoding UTF8
$encodesEmail = $modelsContent -match 'try container\.encode\(.*email.*\)'
Test-Assert "Rule R1/R4: SlooshUser does not encode email into public DTO" (!$encodesEmail)

# 5. Check Firebase Realtime DB REST paths (R1/R4)
$repoContent = Get-Content -Path "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\Data\Repositories\MessengerRepository.swift" -Raw -Encoding UTF8
$hasChannelTagsPath = $repoContent -match 'channelTags/'
$hasUserTagsPath = $repoContent -match 'userTags/'
$hasSanitizedProfileSync = $repoContent -match 'syncCurrentUserProfile'
Test-Assert "Rule R1/R4: Firebase RTDB channelTags index used" $hasChannelTagsPath
Test-Assert "Rule R1/R4: Firebase RTDB userTags index used" $hasUserTagsPath
Test-Assert "Rule R1/R4: Sanitized profile sync implemented" $hasSanitizedProfileSync

# 6. Check PhotosPicker and Avatar Compression (R2)
$avatarProcessorContent = Get-Content -Path "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Shared\AvatarImageProcessor.swift" -Raw -Encoding UTF8
$hasMaxDim256 = $avatarProcessorContent -match 'maxDimension.*256'
$hasMaxBytes50KB = $avatarProcessorContent -match '50 \* 1024'
$hasBase64DataUri = $avatarProcessorContent -match 'data:image/jpeg;base64'
Test-Assert "Rule R2: Avatar processor maxDimension is 256x256" $hasMaxDim256
Test-Assert "Rule R2: Avatar processor maxBytes is < 50KB (50 * 1024)" $hasMaxBytes50KB
Test-Assert "Rule R2: Avatar processor outputs base64 JPEG Data URI" $hasBase64DataUri

# 7. Check SlooshAvatarView Liquid Glass fallback (R2/R3)
$avatarViewContent = Get-Content -Path "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Shared\SlooshAvatarView.swift" -Raw -Encoding UTF8
$hasGlassEffectCircle = $avatarViewContent -match 'glassEffect.*Circle\(\)'
Test-Assert "Rule R2/R3: SlooshAvatarView fallback uses Liquid Glass circle" $hasGlassEffectCircle

# 8. Check Git status & push (Project Rules)
$gitLog = git -C "W:\iOS-sloosh\sloosh-iOS" log -n 1 --oneline
Test-Assert "Project Rules: Changes committed to git" ($gitLog -match "feat\(messenger\)")

$gitDiff = git -C "W:\iOS-sloosh\sloosh-iOS" status --porcelain
$untrackedInApp = $gitDiff | Where-Object { $_ -match "sloosh-iOS/sloosh" }
Test-Assert "Project Rules: Working tree clean in sloosh-iOS" ($null -eq $untrackedInApp -or $untrackedInApp.Count -eq 0)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "AUDIT RESULTS: $passed PASSED, $failed FAILED" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if ($failed -gt 0) {
    exit 1
}
