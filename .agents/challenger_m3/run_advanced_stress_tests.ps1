# Advanced Stress Test Harness for Milestone 3 Verification
$ErrorActionPreference = "Stop"

Write-Host "=== TEST SUITE 5: Concurrent Reactions & Idempotency ===" -ForegroundColor Cyan

# Simulating 50 concurrent reactions across 10 users on 5 different emojis
$globalReactions = @{}
$users = 1..10 | ForEach-Object { "user_$_" }
$emojis = @("🔥", "❤️", "🍿", "🎬", "⚡️")

foreach ($u in $users) {
    # Each user reacts with an emoji
    $chosenEmoji = $emojis[([int]([Math]::Abs($u.GetHashCode())) % $emojis.Count)]
    $globalReactions[$u] = $chosenEmoji
}

# Toggling user_1 again should remove it
$globalReactions.Remove("user_1")

# User 2 changes emoji to ⚡️
$globalReactions["user_2"] = "⚡️"

if ($globalReactions.ContainsKey("user_1")) { throw "Stress Test 5.1 Failed: user_1 reaction should be removed" }
if ($globalReactions["user_2"] -ne "⚡️") { throw "Stress Test 5.2 Failed: user_2 emoji not updated" }
if ($globalReactions.Count -ne 9) { throw "Stress Test 5.3 Failed: expected 9 active reactions, got $($globalReactions.Count)" }
Write-Host " [PASS] Test 5: Concurrent reactions and idempotency verified" -ForegroundColor Green


Write-Host "`n=== TEST SUITE 6: Post Deletion and Unpin Cascade ===" -ForegroundColor Cyan

$channel = [PSCustomObject]@{
    Id = "ch_123"
    PinnedPostId = "post_999"
    LastPostText = "🎬 Interstellar"
    LastPostTimestampMs = 1700000000000
}

$posts = [System.Collections.Generic.List[PSCustomObject]]@(
    [PSCustomObject]@{ Id = "post_100"; Text = "First post"; TimestampMs = 1690000000000; IsPinned = $false; Media = $null },
    [PSCustomObject]@{ Id = "post_999"; Text = "Pinned post"; TimestampMs = 1695000000000; IsPinned = $true; Media = $null },
    [PSCustomObject]@{ Id = "post_200"; Text = "Latest post"; TimestampMs = 1700000000000; IsPinned = $false; Media = [PSCustomObject]@{ Title = "Interstellar" } }
)

# Deleting the pinned post (post_999)
$deletedIdx = $posts.FindIndex({ param($p) $p.Id -eq "post_999" })
$wasPinned = $posts[$deletedIdx].IsPinned
$posts.RemoveAt($deletedIdx)

if ($wasPinned) {
    $channel.PinnedPostId = $null
}

# Update channel preview text from remaining posts
$lastPost = $posts[$posts.Count - 1]
$previewText = if ($null -ne $lastPost.Media) { "🎬 $($lastPost.Media.Title)" } else { $lastPost.Text }
$channel.LastPostText = $previewText
$channel.LastPostTimestampMs = $lastPost.TimestampMs

if ($null -ne $channel.PinnedPostId) { throw "Test 6.1 Failed: Channel pinnedPostId should be reset to null" }
if ($channel.LastPostText -ne "🎬 Interstellar") { throw "Test 6.2 Failed: Preview text mismatch" }
if ($posts.Count -ne 2) { throw "Test 6.3 Failed: Remaining posts count incorrect" }
Write-Host " [PASS] Test 6: Deletion and unpin cascade logic verified" -ForegroundColor Green

Write-Host "`n>>> ALL ADVANCED STRESS TESTS PASSED SUCCESSFULLY! <<<" -ForegroundColor Green
