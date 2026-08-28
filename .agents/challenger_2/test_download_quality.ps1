# Pure PowerShell implementation of DownloadManager stream selection logic

function Extract-HeightFromUrlString([string]$urlString) {
    if ([string]::IsNullOrEmpty($urlString)) { return 0 }
    $pathWithoutQuery = $urlString.Split('?')[0].ToLowerInvariant()
    $pattern = '(?:^|[/._\-])(2160|1440|1080|720|480|360|240)(?:p)?(?:\.m3u8|[/._\-]|$)'
    $match = [regex]::Match($pathWithoutQuery, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success -and $match.Groups.Count -ge 2) {
        $val = 0
        if ([int]::TryParse($match.Groups[1].Value, [ref]$val)) {
            return $val
        }
    }
    return 0
}

function Choose-MediaPlaylistUrl([string]$content, [System.Uri]$baseUrl, [string]$preferredQuality) {
    $lines = $content.Replace("`r`n", "`n").Replace("`r", "`n").Split("`n")
    $variants = @()
    $currentBandwidth = 0.0
    $currentHeight = 0
    $isAv1 = $false
    $hasStreamInf = $false

    foreach ($rawLine in $lines) {
        $trimmed = $rawLine.Trim()
        if ([string]::IsNullOrEmpty($trimmed)) { continue }

        if ($trimmed.StartsWith("#EXT-X-STREAM-INF:")) {
            $hasStreamInf = $true
            $currentBandwidth = 0.0
            $currentHeight = 0
            $isAv1 = $false

            $lower = $trimmed.ToLowerInvariant()

            # Parse CODECS and filter out AV1 streams
            if ($lower.Contains("av01") -or $lower.Contains('codecs="av01') -or $lower.Contains('codecs="av1') -or $lower.Contains("codecs='av1")) {
                $isAv1 = $true
            }

            # Parse BANDWIDTH or AVERAGE-BANDWIDTH
            $bwMatch = [regex]::Match($trimmed, 'BANDWIDTH=([0-9]+)')
            if ($bwMatch.Success -and $bwMatch.Groups.Count -eq 2) {
                $bwVal = 0.0
                if ([double]::TryParse($bwMatch.Groups[1].Value, [ref]$bwVal)) {
                    $currentBandwidth = $bwVal
                }
            } else {
                $avgBwMatch = [regex]::Match($trimmed, 'AVERAGE-BANDWIDTH=([0-9]+)')
                if ($avgBwMatch.Success -and $avgBwMatch.Groups.Count -eq 2) {
                    $avgBwVal = 0.0
                    if ([double]::TryParse($avgBwMatch.Groups[1].Value, [ref]$avgBwVal)) {
                        $currentBandwidth = $avgBwVal
                    }
                }
            }

            # Parse RESOLUTION=WxH
            $resMatch = [regex]::Match($trimmed, 'RESOLUTION=([0-9]+)x([0-9]+)')
            if ($resMatch.Success -and $resMatch.Groups.Count -eq 3) {
                $hVal = 0
                if ([int]::TryParse($resMatch.Groups[2].Value, [ref]$hVal)) {
                    $currentHeight = $hVal
                }
            }
        } elseif ($hasStreamInf -and -not $trimmed.StartsWith("#")) {
            $hasStreamInf = $false

            $lowerUrl = $trimmed.ToLowerInvariant()
            if ($lowerUrl.Contains("av01") -or $lowerUrl.Contains("_av1") -or $lowerUrl.Contains(".av1")) {
                $isAv1 = $true
            }

            if ($isAv1) {
                continue
            }

            if ($currentHeight -eq 0) {
                $currentHeight = Extract-HeightFromUrlString $trimmed
            }

            $variantUrl = $null
            if ($trimmed.StartsWith("http", [System.StringComparison]::OrdinalIgnoreCase)) {
                $uriResult = $null
                if ([System.Uri]::TryCreate($trimmed, [System.UriKind]::Absolute, [ref]$uriResult)) {
                    $variantUrl = $uriResult
                }
            } else {
                $uriResult = $null
                if ([System.Uri]::TryCreate($baseUrl, $trimmed, [ref]$uriResult)) {
                    $variantUrl = $uriResult
                }
            }

            if ($variantUrl -ne $null) {
                $variants += [PSCustomObject]@{
                    Url = $variantUrl
                    Height = $currentHeight
                    Bandwidth = $currentBandwidth
                }
            }
        }
    }

    if ($variants.Count -eq 0) { return $null }

    $targetHeight = 1080
    switch ($preferredQuality) {
        "1080p" { $targetHeight = 1080 }
        "720p"  { $targetHeight = 720 }
        "480p"  { $targetHeight = 480 }
        "360p"  { $targetHeight = 360 }
        default { $targetHeight = 1080 }
    }

    # Select the variant with highest resolution <= targetHeight, tie-breaking on highest bandwidth
    $eligible = $variants | Where-Object { $_.Height -gt 0 -and $_.Height -le $targetHeight }
    if ($eligible -ne $null -and @($eligible).Count -gt 0) {
        $sorted = @($eligible) | Sort-Object -Property @{Expression={$_.Height}; Descending=$true}, @{Expression={$_.Bandwidth}; Descending=$true}
        return $sorted[0].Url
    }

    # Fallback to closest available resolution
    $sortedFallback = @($variants) | Sort-Object -Property @{Expression={if ($_.Height -gt 0) { [Math]::Abs($_.Height - $targetHeight) } else { [int]::MaxValue }}; Descending=$false}, @{Expression={$_.Height}; Descending=$true}, @{Expression={$_.Bandwidth}; Descending=$true}
    return $sortedFallback[0].Url
}

$global:testsPassed = 0
$global:testsFailed = 0

function Assert-Equal($actual, $expected, $testName) {
    if ($actual -eq $expected) {
        Write-Host "[PASS] $testName" -ForegroundColor Green
        $global:testsPassed++
    } else {
        Write-Host "[FAIL] $testName - Expected: '$expected', Actual: '$actual'" -ForegroundColor Red
        $global:testsFailed++
    }
}

Write-Host "=== TEST SUITE 1: URL Height Extraction ===" -ForegroundColor Cyan

Assert-Equal (Extract-HeightFromUrlString "https://cdn.example.com/hls/1080.m3u8") 1080 "1080.m3u8"
Assert-Equal (Extract-HeightFromUrlString "https://cdn.example.com/hls/1080p/index.m3u8") 1080 "1080p/index.m3u8"
Assert-Equal (Extract-HeightFromUrlString "tracks-v1/720.m3u8") 720 "tracks-v1/720.m3u8"
Assert-Equal (Extract-HeightFromUrlString "video_720p.m3u8?token=123") 720 "video_720p.m3u8 with query"
Assert-Equal (Extract-HeightFromUrlString "manifest_480p.m3u8") 480 "manifest_480p.m3u8"
Assert-Equal (Extract-HeightFromUrlString "360p.m3u8") 360 "360p.m3u8"
Assert-Equal (Extract-HeightFromUrlString "240p/manifest.m3u8") 240 "240p/manifest.m3u8"
Assert-Equal (Extract-HeightFromUrlString "2160.m3u8") 2160 "2160.m3u8 (4K)"
Assert-Equal (Extract-HeightFromUrlString "1440p/video.m3u8") 1440 "1440p/video.m3u8 (2K)"
Assert-Equal (Extract-HeightFromUrlString "stream_high.m3u8") 0 "stream_high.m3u8 (no resolution cue)"

Write-Host "`n=== TEST SUITE 2: Standard Master Playlist with RESOLUTION & BANDWIDTH ===" -ForegroundColor Cyan

$baseUrl = [System.Uri]"https://alloha.cdn.net/hls/master.m3u8"
$playlist1 = @"
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=854x480
480.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
1080.m3u8
"@

$res1080 = Choose-MediaPlaylistUrl $playlist1 $baseUrl "1080p"
Assert-Equal $res1080.AbsoluteUri "https://alloha.cdn.net/hls/1080.m3u8" "Requested 1080p -> selects 1080.m3u8"

$res720 = Choose-MediaPlaylistUrl $playlist1 $baseUrl "720p"
Assert-Equal $res720.AbsoluteUri "https://alloha.cdn.net/hls/720.m3u8" "Requested 720p -> selects 720.m3u8"

$res480 = Choose-MediaPlaylistUrl $playlist1 $baseUrl "480p"
Assert-Equal $res480.AbsoluteUri "https://alloha.cdn.net/hls/480.m3u8" "Requested 480p -> selects 480.m3u8"

$res360 = Choose-MediaPlaylistUrl $playlist1 $baseUrl "360p"
Assert-Equal $res360.AbsoluteUri "https://alloha.cdn.net/hls/360.m3u8" "Requested 360p -> selects 360.m3u8"

Write-Host "`n=== TEST SUITE 3: Bandwidth Tie-Breaking at Same Resolution ===" -ForegroundColor Cyan

$playlistTie = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080
1080_low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080
1080_high.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
1080_mid.m3u8
"@
$resTie = Choose-MediaPlaylistUrl $playlistTie $baseUrl "1080p"
Assert-Equal $resTie.AbsoluteUri "https://alloha.cdn.net/hls/1080_high.m3u8" "Tie breaker on highest bandwidth (8000000) for 1080p"

Write-Host "`n=== TEST SUITE 4: Resolution Only in URL Path (No RESOLUTION Attribute) ===" -ForegroundColor Cyan

$playlistUrlOnly = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000
tracks-v1/360p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000
tracks-v1/480p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000
tracks-v1/720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000
tracks-v1/1080p.m3u8
"@
$resUrl1080 = Choose-MediaPlaylistUrl $playlistUrlOnly $baseUrl "1080p"
Assert-Equal $resUrl1080.AbsoluteUri "https://alloha.cdn.net/hls/tracks-v1/1080p.m3u8" "URL cue detection selects 1080p when RESOLUTION is missing"

$resUrl720 = Choose-MediaPlaylistUrl $playlistUrlOnly $baseUrl "720p"
Assert-Equal $resUrl720.AbsoluteUri "https://alloha.cdn.net/hls/tracks-v1/720p.m3u8" "URL cue detection selects 720p when RESOLUTION is missing"

Write-Host "`n=== TEST SUITE 5: AV1 Filtering with Codecs or Filenames ===" -ForegroundColor Cyan

$playlistAv1 = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1920x1080,CODECS="av01.0.04M.08,mp4a.40.2"
1080_av1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
1080_h264.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
720_h264.m3u8
"@
$resAv1Filter = Choose-MediaPlaylistUrl $playlistAv1 $baseUrl "1080p"
Assert-Equal $resAv1Filter.AbsoluteUri "https://alloha.cdn.net/hls/1080_h264.m3u8" "AV1 1080p stream is filtered out, selects H.264 1080p stream"

$playlistAv1Only1080 = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1920x1080,CODECS="av01.0.04M.08,mp4a.40.2"
1080_av1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
720_h264.m3u8
"@
$resAv1Fallback = Choose-MediaPlaylistUrl $playlistAv1Only1080 $baseUrl "1080p"
Assert-Equal $resAv1Fallback.AbsoluteUri "https://alloha.cdn.net/hls/720_h264.m3u8" "When 1080p is only AV1, falls back to 720p H.264"

Write-Host "`n=== TEST SUITE 6: Best Available <= Target Resolution (No 1080p Available) ===" -ForegroundColor Cyan

$playlistMax720 = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=854x480
480.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
720.m3u8
"@
$resMax720 = Choose-MediaPlaylistUrl $playlistMax720 $baseUrl "1080p"
Assert-Equal $resMax720.AbsoluteUri "https://alloha.cdn.net/hls/720.m3u8" "User asks for 1080p on 720p-max title -> selects 720.m3u8"

Write-Host "`n=== TEST SUITE 7: 4K Available but User Requests 1080p ===" -ForegroundColor Cyan

$playlist4k = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=15000000,RESOLUTION=3840x2160
4k_2160.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
720.m3u8
"@
$res4k = Choose-MediaPlaylistUrl $playlist4k $baseUrl "1080p"
Assert-Equal $res4k.AbsoluteUri "https://alloha.cdn.net/hls/1080.m3u8" "User asks for 1080p on 4K title -> selects 1080.m3u8 (does not download 4K)"

Write-Host "`n=== TEST SUITE 8: Absolute HTTP URLs in Master Playlist ===" -ForegroundColor Cyan

$playlistAbsolute = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
https://edge1.cdn.com/hls/720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
https://edge2.cdn.com/hls/1080p.m3u8
"@
$resAbs = Choose-MediaPlaylistUrl $playlistAbsolute $baseUrl "1080p"
Assert-Equal $resAbs.AbsoluteUri "https://edge2.cdn.com/hls/1080p.m3u8" "Absolute URL variant correctly preserved"

Write-Host "`n=== TEST SUITE 9: Windows CRLF and Empty Lines Robustness ===" -ForegroundColor Cyan

$playlistCrlf = "#EXTM3U`r`n`r`n#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720`r`n`r`n720.m3u8`r`n`r`n#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080`r`n`r`n1080.m3u8`r`n"
$resCrlf = Choose-MediaPlaylistUrl $playlistCrlf $baseUrl "1080p"
Assert-Equal $resCrlf.AbsoluteUri "https://alloha.cdn.net/hls/1080.m3u8" "CRLF and empty lines handled without error"

Write-Host "`n=========================================="
Write-Host "Total Tests: $($global:testsPassed + $global:testsFailed)"
Write-Host "Passed: $global:testsPassed" -ForegroundColor Green
Write-Host "Failed: $global:testsFailed" -ForegroundColor $(if ($global:testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "=========================================="

if ($global:testsFailed -gt 0) { exit 1 } else { exit 0 }
