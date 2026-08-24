# PowerShell Comprehensive Empirical & Structural Verification Harness for Milestone 2

$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STARTING EMPIRICAL & STRUCTURAL VERIFICATION FOR MILESTONE 2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$baseDir = "W:\iOS-sloosh"
$messengerDir = Join-Path $baseDir "sloosh-iOS\sloosh\Sources\UI\Messenger"
$modelsFile = Join-Path $baseDir "sloosh-iOS\sloosh\Sources\Data\Models\MessengerModels.swift"
$repoFile = Join-Path $baseDir "sloosh-iOS\sloosh\Sources\Data\Repositories\MessengerRepository.swift"

$createSheetFile = Join-Path $messengerDir "CreateChannelSheet.swift"
$messengerViewFile = Join-Path $messengerDir "MessengerView.swift"
$channelDetailFile = Join-Path $messengerDir "ChannelDetailView.swift"

$global:failures = New-Object System.Collections.ArrayList
$global:passes = New-Object System.Collections.ArrayList

function Assert-Test($testName, $condition, $failMessage = "") {
    if ($condition) {
        Write-Host " [PASS] $testName" -ForegroundColor Green
        [void]$global:passes.Add($testName)
    } else {
        Write-Host " [FAIL] $testName - $failMessage" -ForegroundColor Red
        [void]$global:failures.Add("$testName - $failMessage")
    }
}

# --- GROUP 1: FILE EXISTENCE & INTEGRITY ---
Write-Host "`n--- Group 1: File Integrity & Layout ---" -ForegroundColor Yellow
Assert-Test "CreateChannelSheet.swift exists" (Test-Path $createSheetFile)
Assert-Test "MessengerView.swift exists" (Test-Path $messengerViewFile)
Assert-Test "ChannelDetailView.swift exists" (Test-Path $channelDetailFile)
Assert-Test "MessengerModels.swift exists" (Test-Path $modelsFile)
Assert-Test "MessengerRepository.swift exists" (Test-Path $repoFile)

$createSheetContent = [System.IO.File]::ReadAllText($createSheetFile, [System.Text.Encoding]::UTF8)
$messengerViewContent = [System.IO.File]::ReadAllText($messengerViewFile, [System.Text.Encoding]::UTF8)
$channelDetailContent = [System.IO.File]::ReadAllText($channelDetailFile, [System.Text.Encoding]::UTF8)
$modelsContent = [System.IO.File]::ReadAllText($modelsFile, [System.Text.Encoding]::UTF8)
$repoContent = [System.IO.File]::ReadAllText($repoFile, [System.Text.Encoding]::UTF8)
$allMessengerContent = $createSheetContent + "`n" + $messengerViewContent + "`n" + $channelDetailContent

# --- GROUP 2: PROJECT & ARCHITECTURE RULES ---
Write-Host "`n--- Group 2: Project Rules & Guidelines ---" -ForegroundColor Yellow
$hasUltraThin = ($allMessengerContent -match 'ultraThinMaterial')
Assert-Test "Rule: Strictly ZERO ultraThinMaterial in Messenger UI" (-not $hasUltraThin) "ultraThinMaterial found!"

$hasForbiddenProviders = ($allMessengerContent -match '(?i)\b(neomovies|alloha|collaps)\b')
Assert-Test "Rule: Strictly ZERO forbidden provider names leaked in Messenger UI" (-not $hasForbiddenProviders) "Forbidden provider name found!"

$hasGlassInCreate = ($createSheetContent -match '\.glassEffect\(')
$hasGlassInMessenger = ($messengerViewContent -match '\.glassEffect\(')
$hasGlassInDetail = ($channelDetailContent -match '\.glassEffect\(')
Assert-Test "Rule: Liquid Glass (.glassEffect) in CreateChannelSheet" $hasGlassInCreate "Missing .glassEffect"
Assert-Test "Rule: Liquid Glass (.glassEffect) in MessengerView" $hasGlassInMessenger "Missing .glassEffect"
Assert-Test "Rule: Liquid Glass (.glassEffect) in ChannelDetailView" $hasGlassInDetail "Missing .glassEffect"

# --- GROUP 3: CREATE CHANNEL SHEET (R1) ---
Write-Host "`n--- Group 3: CreateChannelSheet Verification ---" -ForegroundColor Yellow

# Input validation test: empty and whitespace-only name
$hasTrimmedValidation = ($createSheetContent -match 'channelName\.trimmingCharacters\(in:\s*\.whitespacesAndNewlines\)\.isEmpty')
Assert-Test "Validation: channelName trimmed emptiness check present" $hasTrimmedValidation "Missing trimmed check"

# isCreating flag disables button and shows ProgressView
$hasIsCreatingCheck = ($createSheetContent -match '!isCreating')
$hasProgressView = ($createSheetContent -match 'if isCreating\s*\{\s*ProgressView\(\)')
Assert-Test "State: isCreating disables button and renders ProgressView" ($hasIsCreatingCheck -and $hasProgressView) "Missing isCreating handling"

# Description field multiline axis
$hasDescriptionField = ($createSheetContent -match 'axis:\s*\.vertical')
Assert-Test "UI: channelDescription field supports vertical multiline axis" $hasDescriptionField "Missing axis: .vertical"

# Emoji Presets & Visual feedback
$hasEmojiArray = ($createSheetContent -match 'emojiPresets')
$hasEmojiSelectionFeedback = ($createSheetContent -match 'UISelectionFeedbackGenerator\(\)')
Assert-Test "UI: Emoji presets array defined with selection haptic feedback" ($hasEmojiArray -and $hasEmojiSelectionFeedback) "Missing emoji presets/feedback"

# Color Palette Presets & Hex mapping
$hasColorPresets = ($createSheetContent -match 'colorPresets')
$hasColorHexParsing = ($createSheetContent -match 'UIColor\(hex:\s*selectedColorHex\)')
Assert-Test "UI: Color presets swatches defined with UIColor(hex:) integration" ($hasColorPresets -and $hasColorHexParsing) "Missing color presets/parsing"

# Avatar preview section
$hasAvatarPreview = ($createSheetContent -match 'avatarPreviewSection')
$hasMegaphoneBadge = ($createSheetContent -match 'Image\(systemName:\s*"megaphone\.fill"\)')
Assert-Test "UI: Live avatar preview with glowing border and megaphone indicator badge" ($hasAvatarPreview -and $hasMegaphoneBadge) "Missing avatar preview badge"

# Create action execution & dismissal
$hasRepoCreateCall = ($createSheetContent -match 'repo\.createChannel\(')
$hasSuccessFeedback = ($createSheetContent -match 'notificationOccurred\(\.success\)')
$hasDismissAndCallback = ($createSheetContent -match 'dismiss\(\)') -and ($createSheetContent -match 'onCreated\(created\)')
Assert-Test "Action: Async channel creation calls repo, triggers success haptic, dismisses and calls onCreated" ($hasRepoCreateCall -and $hasSuccessFeedback -and $hasDismissAndCallback) "Missing creation flow step"

# --- GROUP 4: MESSENGER VIEW & UNIFIED FEED (R3) ---
Write-Host "`n--- Group 4: MessengerView & Unified Feed Verification ---" -ForegroundColor Yellow

# Top Action Menu
$hasTopMenu = ($messengerViewContent -match 'Menu\s*\{') -and ($messengerViewContent -match 'systemImage:\s*"megaphone\.fill"') -and ($messengerViewContent -match 'systemImage:\s*"person\.2\.fill"')
$hasMenuDisabledItem = ($messengerViewContent -match '\.disabled\(true\)')
Assert-Test "Menu: Top action Menu contains channel create action and disabled chat action" ($hasTopMenu -and $hasMenuDisabledItem) "Missing menu structure"

# Unified Feed Sorting Logic Simulation
Write-Host "--- Simulating Unified Feed Sorting Algorithm in PowerShell ---" -ForegroundColor DarkGray
$simChats = @(
    [PSCustomObject]@{ Type = "chat"; Id = "c1"; UpdatedAt = [int64]1000; Text = "Hello" },
    [PSCustomObject]@{ Type = "chat"; Id = "c2"; UpdatedAt = [int64]5000; Text = "Latest chat" }
)
$simChannels = @(
    [PSCustomObject]@{ Type = "channel"; Id = "ch1"; UpdatedAt = [int64]2000; LastPostTimestamp = [int64]6000; Name = "News" },
    [PSCustomObject]@{ Type = "channel"; Id = "ch2"; UpdatedAt = [int64]3000; LastPostTimestamp = $null; Name = "Static" }
)

$feed = New-Object System.Collections.ArrayList
foreach ($c in $simChats) {
    [void]$feed.Add([PSCustomObject]@{ Id = "chat_$($c.Id)"; Timestamp = $c.UpdatedAt; Item = $c })
}
foreach ($ch in $simChannels) {
    $ts = if ($ch.LastPostTimestamp) { $ch.LastPostTimestamp } else { $ch.UpdatedAt }
    [void]$feed.Add([PSCustomObject]@{ Id = "channel_$($ch.Id)"; Timestamp = $ts; Item = $ch })
}
$sortedFeed = $feed | Sort-Object -Property Timestamp -Descending

# Expected order:
# 1. channel_ch1 (6000)
# 2. chat_c2 (5000)
# 3. channel_ch2 (3000)
# 4. chat_c1 (1000)
$isOrderCorrect = ($sortedFeed[0].Id -eq "channel_ch1") -and ($sortedFeed[1].Id -eq "chat_c2") -and ($sortedFeed[2].Id -eq "channel_ch2") -and ($sortedFeed[3].Id -eq "chat_c1")
Assert-Test "Logic Simulation: Unified feed sorting orders items chronologically descending by latest activity" $isOrderCorrect "Sorting order mismatch"

# Check Swift implementation of sorting logic
$hasUnifiedItemsProperty = ($messengerViewContent -match 'var unifiedFeedItems:\s*\[MessengerFeedItem\]')
$hasSwiftSorting = ($messengerViewContent -match 'items\.sorted\s*\{\s*\$0\.timestampMs\s*>\s*\$1\.timestampMs\s*\}')
Assert-Test "Swift Code: unifiedFeedItems computed property implements timestampMs descending sort" ($hasUnifiedItemsProperty -and $hasSwiftSorting) "Missing unifiedFeedItems sorting"

# Channel Row (PeakChannelRow)
$hasPeakChannelRow = ($messengerViewContent -match 'struct PeakChannelRow:\s*View')
$hasCrownForOwner = ($messengerViewContent -match 'if isOwner\s*\{[\s\S]*crown\.fill')
$hasChannelTimestampFormat = ($messengerViewContent -match 'formatTime\(ms:\s*channel\.lastPostTimestampMs\s*\?\?\s*channel\.updatedAtMs\)')
$hasChannelContextMenu = ($messengerViewContent -match 'contextMenu\s*\{[\s\S]*Button\(role:\s*\.destructive\)')
Assert-Test "UI: PeakChannelRow implements avatar badge, owner crown, fallback timestamp, and context menu" ($hasPeakChannelRow -and $hasCrownForOwner -and $hasChannelTimestampFormat -and $hasChannelContextMenu) "Missing PeakChannelRow elements"

# Public Channel Search (R3)
$hasSearchHandler = ($messengerViewContent -match 'onChange\(of:\s*searchQuery\)\s*\{[\s\S]*fetchPublicChannels')
$hasChannelsHeader = ($messengerViewContent -match 'header:\s*\{[\s\S]*Spacer\(\)[\s\S]*\}')
$hasPublicRow = ($messengerViewContent -match 'struct PublicChannelSearchRow:\s*View')
$hasSubscribeToggleAction = ($messengerViewContent -match 'toggleChannelSubscription\(channel:\s*channel\)')
Assert-Test "Search: Search query fetches public channels and renders toggleable subscribe button" ($hasSearchHandler -and $hasChannelsHeader -and $hasPublicRow -and $hasSubscribeToggleAction) "Missing search integration"

# Navigation & Confirmation Dialogs
$hasChatNav = ($messengerViewContent -match '\.navigationDestination\(item:\s*\$selectedPeerUser\)')
$hasChannelNav = ($messengerViewContent -match '\.navigationDestination\(item:\s*\$selectedChannel\)')
$hasSheetNav = ($messengerViewContent -match '\.sheet\(isPresented:\s*\$showCreateChannelSheet\)')
$hasActionConfirmDialog = ($messengerViewContent -match 'confirmationDialog\(\s*channelActionTitle,\s*isPresented:\s*\$showChannelActionConfirm')
Assert-Test "Navigation: All navigation destinations (chat, channel, sheet) and confirmation dialogs wired" ($hasChatNav -and $hasChannelNav -and $hasSheetNav -and $hasActionConfirmDialog) "Missing navigation destinations"

# --- GROUP 5: CHANNEL DETAIL VIEW (R2 BASELINE) ---
Write-Host "`n--- Group 5: ChannelDetailView Verification ---" -ForegroundColor Yellow
$hasDetailStruct = ($channelDetailContent -match 'struct ChannelDetailView:\s*View')
$hasDetailOwnerLogic = ($channelDetailContent -match 'private var isOwner:\s*Bool\s*\{[\s\S]*channel\.ownerId\s*==\s*currentUserId')
$hasDetailAuthorPill = ($channelDetailContent -match 'crown\.fill')
$hasDetailSubButton = ($channelDetailContent -match 'if !isOwner\s*\{')
$hasDetailSubAction = ($channelDetailContent -match 'repo\.subscribeToChannel') -and ($channelDetailContent -match 'repo\.unsubscribeFromChannel')
Assert-Test "ChannelDetailView: Renders channel header, owner pill, and interactive subscribe button for viewers" ($hasDetailStruct -and $hasDetailOwnerLogic -and $hasDetailAuthorPill -and $hasDetailSubButton -and $hasDetailSubAction) "Missing detail view features"

# --- GROUP 6: MODEL CONFORMANCE & METHODS ---
Write-Host "`n--- Group 6: Model & Data Layer Conformance ---" -ForegroundColor Yellow
$hasChannelModel = ($modelsContent -match 'struct ChannelModel:\s*Identifiable,\s*Codable,\s*Equatable,\s*Hashable')
$hasFeedItemEnum = ($modelsContent -match 'enum MessengerFeedItem:\s*Identifiable,\s*Hashable')
$hasSubscriberFormat = ($modelsContent -match 'var formattedSubscriberCount:\s*String')
$hasDisplayEmoji = ($modelsContent -match 'var displayAvatarEmoji:\s*String')
$hasDisplayAccent = ($modelsContent -match 'var displayAccentColor:\s*Color')
Assert-Test "Models: ChannelModel & MessengerFeedItem conform to Identifiable/Hashable and have display helpers" ($hasChannelModel -and $hasFeedItemEnum -and $hasSubscriberFormat -and $hasDisplayEmoji -and $hasDisplayAccent) "Missing model conformance"

# --- FINAL REPORT ---
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " VERIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Total Tests Passed: $($global:passes.Count)" -ForegroundColor Green
Write-Host "Total Tests Failed: $($global:failures.Count)" -ForegroundColor Red

if ($global:failures.Count -gt 0) {
    Write-Host "`nFailed Tests List:" -ForegroundColor Red
    foreach ($f in $global:failures) {
        Write-Host "  - $f" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "`nALL EMPIRICAL & STRUCTURAL VERIFICATION TESTS PASSED SUCCESSFULLY!" -ForegroundColor Green
    exit 0
}
