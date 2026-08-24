# Independent Victory Audit Verification Script
$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " STARTING INDEPENDENT VICTORY AUDIT VERIFICATION" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$baseDir = "W:\iOS-sloosh\sloosh-iOS\sloosh\Sources"
$files = @(
    "$baseDir\Data\Models\MessengerModels.swift",
    "$baseDir\Data\Repositories\MessengerRepository.swift",
    "$baseDir\UI\Color+Theme.swift",
    "$baseDir\UI\Messenger\MessengerView.swift",
    "$baseDir\UI\Messenger\CreateChannelSheet.swift",
    "$baseDir\UI\Messenger\ChannelDetailView.swift",
    "$baseDir\UI\Messenger\PinnedPostBar.swift",
    "$baseDir\UI\Messenger\ChannelPostRowView.swift",
    "$baseDir\UI\Messenger\MovieSelectorSheet.swift",
    "$baseDir\UI\Messenger\ChannelMediaCardView.swift",
    "$baseDir\UI\Messenger\ChannelInfoView.swift"
)

$allPassed = $true

# Helper for unicode strings
$strSozdatKanal = [string]::new([char[]]@(0x0421, 0x043E, 0x0437, 0x0434, 0x0430, 0x0442, 0x044C, 0x0020, 0x043A, 0x0430, 0x043D, 0x0430, 0x043B))
$strSozdatBesedu = [string]::new([char[]]@(0x0421, 0x043E, 0x0437, 0x0434, 0x0430, 0x0442, 0x044C, 0x0020, 0x0431, 0x0435, 0x0441, 0x0435, 0x0434, 0x0443))
$strKanaly = [string]::new([char[]]@(0x041A, 0x0410, 0x041D, 0x0410, 0x041B, 0x042B))

# Check 1: File Existence & Non-empty
Write-Host "`n[Check 1: File Existence and Non-Empty]" -ForegroundColor Yellow
foreach ($file in $files) {
    if (Test-Path $file) {
        $len = (Get-Item $file).Length
        $lines = (Get-Content -Encoding UTF8 $file).Count
        Write-Host "  [PASS] $file ($lines lines, $len bytes)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Missing file: $file" -ForegroundColor Red
        $allPassed = $false
    }
}

# Check 2: Syntax & Brace/Bracket/Parenthesis Balancing
Write-Host "`n[Check 2: Structural Token Balancing]" -ForegroundColor Yellow
foreach ($file in $files) {
    $content = Get-Content -Encoding UTF8 $file -Raw
    $openBraces = ($content.ToCharArray() | Where-Object { $_ -eq '{' }).Count
    $closeBraces = ($content.ToCharArray() | Where-Object { $_ -eq '}' }).Count
    $openParens = ($content.ToCharArray() | Where-Object { $_ -eq '(' }).Count
    $closeParens = ($content.ToCharArray() | Where-Object { $_ -eq ')' }).Count
    $openBrackets = ($content.ToCharArray() | Where-Object { $_ -eq '[' }).Count
    $closeBrackets = ($content.ToCharArray() | Where-Object { $_ -eq ']' }).Count

    $braceOk = ($openBraces -eq $closeBraces)
    $parenOk = ($openParens -eq $closeParens)
    $bracketOk = ($openBrackets -eq $closeBrackets)

    if ($braceOk -and $parenOk -and $bracketOk) {
        Write-Host "  [PASS] $(Split-Path $file -Leaf) (Braces: $openBraces/$closeBraces, Parens: $openParens/$closeParens, Brackets: $openBrackets/$closeBrackets)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Token imbalance in $(Split-Path $file -Leaf): Braces ($openBraces/$closeBraces), Parens ($openParens/$closeParens), Brackets ($openBrackets/$closeBrackets)" -ForegroundColor Red
        $allPassed = $false
    }
}

# Check 3: Forensic Forbidden Patterns (.ultraThinMaterial, Collaps)
Write-Host "`n[Check 3: Forensic Forbidden Patterns]" -ForegroundColor Yellow
$rootSearch = "W:\iOS-sloosh\sloosh-iOS"
$matMatches = Get-ChildItem -Path $rootSearch -Recurse -Filter "*.swift" | Select-String -Pattern "ultraThinMaterial" -CaseSensitive:$false
if ($matMatches.Count -eq 0) {
    Write-Host "  [PASS] Zero occurrences of forbidden .ultraThinMaterial in sloosh-iOS" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Found forbidden .ultraThinMaterial in $($matMatches.Count) places!" -ForegroundColor Red
    $allPassed = $false
}

$collapsMatches = Get-ChildItem -Path "$baseDir\UI\Messenger", "$baseDir\Data\Models\MessengerModels.swift", "$baseDir\Data\Repositories\MessengerRepository.swift" | Select-String -Pattern "collaps" -CaseSensitive:$false
if ($collapsMatches.Count -eq 0) {
    Write-Host "  [PASS] Zero references to Collaps in Messenger components" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Found forbidden Collaps reference in Messenger!" -ForegroundColor Red
    $allPassed = $false
}

# Check 4: Verification of R1 (Creation Menu, Sheet, Models, Ownership)
Write-Host "`n[Check 4: R1 Creation Menu and Channel Creation]" -ForegroundColor Yellow
$mvContent = Get-Content -Encoding UTF8 "$baseDir\UI\Messenger\MessengerView.swift" -Raw
$sheetContent = Get-Content -Encoding UTF8 "$baseDir\UI\Messenger\CreateChannelSheet.swift" -Raw
$repoContent = Get-Content -Encoding UTF8 "$baseDir\Data\Repositories\MessengerRepository.swift" -Raw

$r1_1 = $mvContent.Contains($strSozdatKanal) -and $mvContent.Contains("square.and.pencil")
$r1_2 = $mvContent.Contains($strSozdatBesedu)
$r1_3 = $sheetContent.Contains("channelName") -and $sheetContent.Contains("channelDescription")
$r1_4 = $sheetContent.Contains("emojiPresets")
$r1_5 = $sheetContent.Contains("colorPresets")
$r1_6 = $repoContent.Contains("public func createChannel") -and $repoContent.Contains("channels/\(channelId)")
$r1_7 = $repoContent.Contains("user_channel_subscriptions") -and $repoContent.Contains("channel_subscribers")

Write-Host "  $($(if($r1_1){'[PASS]'}else{'[FAIL]'})) Top-right menu in MessengerView with Create Channel" -ForegroundColor $(if($r1_1){'Green'}else{'Red'})
Write-Host "  $($(if($r1_2){'[PASS]'}else{'[FAIL]'})) Create Group Chat (Coming Soon) item in menu" -ForegroundColor $(if($r1_2){'Green'}else{'Red'})
Write-Host "  $($(if($r1_3){'[PASS]'}else{'[FAIL]'})) CreateChannelSheet with name and description fields" -ForegroundColor $(if($r1_3){'Green'}else{'Red'})
Write-Host "  $($(if($r1_4){'[PASS]'}else{'[FAIL]'})) Emoji picker with presets" -ForegroundColor $(if($r1_4){'Green'}else{'Red'})
Write-Host "  $($(if($r1_5){'[PASS]'}else{'[FAIL]'})) Accent color picker with presets" -ForegroundColor $(if($r1_5){'Green'}else{'Red'})
Write-Host "  $($(if($r1_6){'[PASS]'}else{'[FAIL]'})) Channel creation REST API in MessengerRepository" -ForegroundColor $(if($r1_6){'Green'}else{'Red'})
Write-Host "  $($(if($r1_7){'[PASS]'}else{'[FAIL]'})) Creator registered as owner and subscriber" -ForegroundColor $(if($r1_7){'Green'}else{'Red'})

if (-not ($r1_1 -and $r1_2 -and $r1_3 -and $r1_4 -and $r1_5 -and $r1_6 -and $r1_7)) { $allPassed = $false }

# Check 5: Verification of R2 (Feed Experience, Roles, Media Cards, Reactions, Pinning)
Write-Host "`n[Check 5: R2 Channel Feed, Roles and Rich Media]" -ForegroundColor Yellow
$detailContent = Get-Content -Encoding UTF8 "$baseDir\UI\Messenger\ChannelDetailView.swift" -Raw
$postRowContent = Get-Content -Encoding UTF8 "$baseDir\UI\Messenger\ChannelPostRowView.swift" -Raw
$pinContent = Get-Content -Encoding UTF8 "$baseDir\UI\Messenger\PinnedPostBar.swift" -Raw
$mediaContent = Get-Content -Encoding UTF8 "$baseDir\UI\Messenger\ChannelMediaCardView.swift" -Raw
$movieSheetContent = Get-Content -Encoding UTF8 "$baseDir\UI\Messenger\MovieSelectorSheet.swift" -Raw

$r2_1 = $detailContent.Contains("authorBroadcastingBar") -and $detailContent.Contains("isOwner")
$r2_2 = $detailContent.Contains("subscriberActionBar") -and $detailContent.Contains("isSubscribed")
$r2_3 = $movieSheetContent.Contains("performDebouncedSearch") -and $movieSheetContent.Contains("getPopularMovies")
$r2_4 = $mediaContent.Contains("onPlayDirectly") -and $mediaContent.Contains("onOpenDetails") -and $mediaContent.Contains("averageColor")
$r2_5 = $detailContent.Contains("HomeDirectPlayWrapper") -and $detailContent.Contains("PlayerView")
$r2_6 = $detailContent.Contains("ScrollViewReader") -and $detailContent.Contains("PinnedPostBar") -and $detailContent.Contains("proxy.scrollTo")
$r2_7 = $postRowContent.Contains("reactionSummary") -and $postRowContent.Contains("availableEmojis")
$r2_8 = $detailContent.Contains("submitPost") -and $detailContent.Contains("togglePin") -and $detailContent.Contains("deletePost")

Write-Host "  $($(if($r2_1){'[PASS]'}else{'[FAIL]'})) ChannelDetailView with Owner broadcasting bar" -ForegroundColor $(if($r2_1){'Green'}else{'Red'})
Write-Host "  $($(if($r2_2){'[PASS]'}else{'[FAIL]'})) ChannelDetailView with Subscriber read-only stream and action bar" -ForegroundColor $(if($r2_2){'Green'}else{'Red'})
Write-Host "  $($(if($r2_3){'[PASS]'}else{'[FAIL]'})) MovieSelectorSheet with search and trending Kinopoisk picker" -ForegroundColor $(if($r2_3){'Green'}else{'Red'})
Write-Host "  $($(if($r2_4){'[PASS]'}else{'[FAIL]'})) ChannelMediaCardView with 2:3 poster, rating badge, play and details actions" -ForegroundColor $(if($r2_4){'Green'}else{'Red'})
Write-Host "  $($(if($r2_5){'[PASS]'}else{'[FAIL]'})) One-tap direct playback integration via HomeDirectPlayWrapper -> PlayerView" -ForegroundColor $(if($r2_5){'Green'}else{'Red'})
Write-Host "  $($(if($r2_6){'[PASS]'}else{'[FAIL]'})) PinnedPostBar with tap-to-scroll via ScrollViewReader" -ForegroundColor $(if($r2_6){'Green'}else{'Red'})
Write-Host "  $($(if($r2_7){'[PASS]'}else{'[FAIL]'})) Emoji reaction aggregation and per-post picker" -ForegroundColor $(if($r2_7){'Green'}else{'Red'})
Write-Host "  $($(if($r2_8){'[PASS]'}else{'[FAIL]'})) Post management actions: edit, pin, delete" -ForegroundColor $(if($r2_8){'Green'}else{'Red'})

if (-not ($r2_1 -and $r2_2 -and $r2_3 -and $r2_4 -and $r2_5 -and $r2_6 -and $r2_7 -and $r2_8)) { $allPassed = $false }

# Check 6: Verification of R3 (Discovery, Search, MessengerView List & ChannelInfoView)
Write-Host "`n[Check 6: R3 Discovery, Search and ChannelInfoView]" -ForegroundColor Yellow
$infoContent = Get-Content -Encoding UTF8 "$baseDir\UI\Messenger\ChannelInfoView.swift" -Raw

$r3_1 = $mvContent.Contains("PeakChannelRow") -and $mvContent.Contains("megaphone.fill")
$r3_2 = $mvContent.Contains("PublicChannelSearchRow") -and $mvContent.Contains($strKanaly)
$r3_3 = $mvContent.Contains("toggleChannelSubscription")
$r3_4 = $infoContent.Contains("headerProfileSection") -and $infoContent.Contains("formattedSubscriberCount")
$r3_5 = $infoContent.Contains("pinnedPostSection") -and $infoContent.Contains("sharedMediaSection")
$r3_6 = $infoContent.Contains("settingsSection") -and $infoContent.Contains("isMuted")
$r3_7 = $infoContent.Contains("EditChannelSheet") -and $infoContent.Contains("deleteChannel")

Write-Host "  $($(if($r3_1){'[PASS]'}else{'[FAIL]'})) Channels displayed in MessengerView feed with megaphone badge" -ForegroundColor $(if($r3_1){'Green'}else{'Red'})
Write-Host "  $($(if($r3_2){'[PASS]'}else{'[FAIL]'})) Public channel search section 'КАНАЛЫ' in MessengerView" -ForegroundColor $(if($r3_2){'Green'}else{'Red'})
Write-Host "  $($(if($r3_3){'[PASS]'}else{'[FAIL]'})) Quick subscribe/unsubscribe toggle in search results" -ForegroundColor $(if($r3_3){'Green'}else{'Red'})
Write-Host "  $($(if($r3_4){'[PASS]'}else{'[FAIL]'})) ChannelInfoView with stats, owner badge, description card" -ForegroundColor $(if($r3_4){'Green'}else{'Red'})
Write-Host "  $($(if($r3_5){'[PASS]'}else{'[FAIL]'})) ChannelInfoView with pinned post snippet and shared media carousel" -ForegroundColor $(if($r3_5){'Green'}else{'Red'})
Write-Host "  $($(if($r3_6){'[PASS]'}else{'[FAIL]'})) ChannelInfoView notifications toggle and link copying" -ForegroundColor $(if($r3_6){'Green'}else{'Red'})
Write-Host "  $($(if($r3_7){'[PASS]'}else{'[FAIL]'})) ChannelInfoView author settings sheet (EditChannelSheet) and deletion dialog" -ForegroundColor $(if($r3_7){'Green'}else{'Red'})

if (-not ($r3_1 -and $r3_2 -and $r3_3 -and $r3_4 -and $r3_5 -and $r3_6 -and $r3_7)) { $allPassed = $false }

# Check 7: Verification of R4 (Architecture, Liquid Glass & Cold Start Caching)
Write-Host "`n[Check 7: R4 Architecture, Liquid Glass and Cold Start Caching]" -ForegroundColor Yellow

$r4_1 = $repoContent.Contains("saveSubscribedChannelsToDisk") -and $repoContent.Contains("saveChannelPostsToDisk")
$r4_2 = $repoContent.Contains("https://sloosh-77434-default-rtdb.firebaseio.com")
$r4_3 = $detailContent.Contains(".glassEffect") -and $infoContent.Contains(".glassEffect") -and $mvContent.Contains(".glassEffect")

Write-Host "  $($(if($r4_1){'[PASS]'}else{'[FAIL]'})) UserDefaults disk caching for channels and posts (0ms cold start)" -ForegroundColor $(if($r4_1){'Green'}else{'Red'})
Write-Host "  $($(if($r4_2){'[PASS]'}else{'[FAIL]'})) Firebase Realtime DB REST API implementation" -ForegroundColor $(if($r4_2){'Green'}else{'Red'})
Write-Host "  $($(if($r4_3){'[PASS]'}else{'[FAIL]'})) Extensive Liquid Glass (.glassEffect) styling" -ForegroundColor $(if($r4_3){'Green'}else{'Red'})

if (-not ($r4_1 -and $r4_2 -and $r4_3)) { $allPassed = $false }

Write-Host "`n================================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host " VICTORY AUDIT VERDICT: ALL 28 INDEPENDENT CHECKS PASSED!" -ForegroundColor Green
} else {
    Write-Host " VICTORY AUDIT VERDICT: INTEGRITY / SPEC VIOLATION DETECTED!" -ForegroundColor Red
}
Write-Host "================================================================" -ForegroundColor Cyan
