# Advanced Empirical Stress Testing and Offline Packaging Verification Harness

function Rewrite-MediaPlaylist([string]$mediaPlaylistContent, [System.Uri]$mediaPlaylistUrl) {
    $lines = $mediaPlaylistContent.Split("`n")
    $segmentUrls = @()
    $segmentLines = @()
    $keyUrl = $null
    $keyLineIndex = $null

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $trimmed = $lines[$i].Trim()
        if ([string]::IsNullOrEmpty($trimmed)) { continue }

        if ($trimmed.StartsWith("#")) {
            if ($trimmed.Contains("URI=")) {
                $match = [regex]::Match($trimmed, 'URI="([^"]+)"')
                if ($match.Success -and $match.Groups.Count -ge 2) {
                    $uriString = $match.Groups[1].Value
                    if (![string]::IsNullOrEmpty($uriString) -and $uriString -ne "none") {
                        if ($uriString.StartsWith("http", [System.StringComparison]::OrdinalIgnoreCase)) {
                            $keyUrl = [System.Uri]$uriString
                        } else {
                            $keyUrl = [System.Uri]::new($mediaPlaylistUrl, $uriString)
                        }
                        $keyLineIndex = $i
                    }
                }
            }
        } else {
            $url = $null
            if ($trimmed.StartsWith("http", [System.StringComparison]::OrdinalIgnoreCase)) {
                $url = [System.Uri]$trimmed
            } else {
                $url = [System.Uri]::new($mediaPlaylistUrl, $trimmed)
            }
            if ($url -ne $null) {
                $segmentUrls += $url
                $segmentLines += $i
            }
        }
    }

    $rewrittenLines = [System.Collections.Generic.List[string]]::new($lines)
    if ($keyLineIndex -ne $null) {
        $origKeyLine = $rewrittenLines[$keyLineIndex]
        $rewrittenLines[$keyLineIndex] = [regex]::Replace($origKeyLine, 'URI="([^"]+)"', 'URI="key.bin"')
    }

    for ($segIdx = 0; $segIdx -lt $segmentLines.Count; $segIdx++) {
        $lineIdx = $segmentLines[$segIdx]
        $rewrittenLines[$lineIdx] = "segment_$segIdx.ts"
    }

    return [PSCustomObject]@{
        KeyUrl = $keyUrl
        SegmentUrls = $segmentUrls
        RewrittenContent = [string]::Join("`n", $rewrittenLines)
    }
}

$global:passed = 0
$global:failed = 0

function Assert-Test($condition, $testName) {
    if ($condition) {
        Write-Host "[PASS] $testName" -ForegroundColor Green
        $global:passed++
    } else {
        Write-Host "[FAIL] $testName" -ForegroundColor Red
        $global:failed++
    }
}

Write-Host "=== TEST SUITE 10: AES-128 Media Playlist Rewriting ===" -ForegroundColor Cyan

$mediaUrl = [System.Uri]"https://alloha.cdn.net/hls/1080/index.m3u8"
$rawMediaPlaylist = @"
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-KEY:METHOD=AES-128,URI="https://keys.alloha.tv/enc.key?id=99281",IV=0x1234567890abcdef1234567890abcdef
#EXTINF:6.000,
seg_001.ts
#EXTINF:6.000,
seg_002.ts
#EXTINF:4.200,
https://storage.alloha.cdn.net/hls/1080/seg_003.ts?auth=token99
#EXT-X-ENDLIST
"@

$parsed = Rewrite-MediaPlaylist $rawMediaPlaylist $mediaUrl

Assert-Test ($parsed.KeyUrl.AbsoluteUri -eq "https://keys.alloha.tv/enc.key?id=99281") "Extracted absolute AES-128 key URL"
Assert-Test ($parsed.SegmentUrls.Count -eq 3) "Extracted 3 segment URLs"
Assert-Test ($parsed.SegmentUrls[0].AbsoluteUri -eq "https://alloha.cdn.net/hls/1080/seg_001.ts") "Relative segment 0 resolved against media base URL"
Assert-Test ($parsed.SegmentUrls[2].AbsoluteUri -eq "https://storage.alloha.cdn.net/hls/1080/seg_003.ts?auth=token99") "Absolute segment 2 preserved with auth token"
Assert-Test ($parsed.RewrittenContent.Contains('URI="key.bin"')) "Key URI rewritten to local 'key.bin'"
Assert-Test ($parsed.RewrittenContent.Contains("segment_0.ts")) "Segment 0 rewritten to 'segment_0.ts'"
Assert-Test ($parsed.RewrittenContent.Contains("segment_1.ts")) "Segment 1 rewritten to 'segment_1.ts'"
Assert-Test ($parsed.RewrittenContent.Contains("segment_2.ts")) "Segment 2 rewritten to 'segment_2.ts'"
Assert-Test ($parsed.RewrittenContent.Contains("#EXT-X-TARGETDURATION:6")) "Preserved header metadata #EXT-X-TARGETDURATION"
Assert-Test ($parsed.RewrittenContent.Contains("#EXT-X-ENDLIST")) "Preserved playlist terminator #EXT-X-ENDLIST"

Write-Host "`n=== TEST SUITE 11: Relative Encryption Key URI ===" -ForegroundColor Cyan

$rawRelativeKey = @"
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="keys/video.key"
#EXTINF:5.0,
seg.ts
#EXT-X-ENDLIST
"@
$parsedRelKey = Rewrite-MediaPlaylist $rawRelativeKey $mediaUrl
Assert-Test ($parsedRelKey.KeyUrl.AbsoluteUri -eq "https://alloha.cdn.net/hls/1080/keys/video.key") "Relative key resolved correctly against base URL"
Assert-Test ($parsedRelKey.RewrittenContent.Contains('URI="key.bin"')) "Relative key rewritten to 'URI=`"key.bin`"'"

Write-Host "`n=== TEST SUITE 12: Complex Master Playlist with Audio Rendezvous & Subtitles ===" -ForegroundColor Cyan

. W:\iOS-sloosh\.agents\challenger_2\test_download_quality.ps1

$complexMaster = @"
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Russian",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="ru",URI="audio/ru/index.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE="en",URI="audio/en/index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Russian",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE="ru",URI="subs/ru.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1200000,AVERAGE-BANDWIDTH=1000000,RESOLUTION=854x480,AUDIO="audio",SUBTITLES="subs"
480p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,AVERAGE-BANDWIDTH=2500000,RESOLUTION=1280x720,AUDIO="audio",SUBTITLES="subs"
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,AVERAGE-BANDWIDTH=5000000,RESOLUTION=1920x1080,AUDIO="audio",SUBTITLES="subs"
1080p/index.m3u8
"@

$cMasterUrl = [System.Uri]"https://alloha.cdn.net/vod/master.m3u8"
$sel1080 = Choose-MediaPlaylistUrl $complexMaster $cMasterUrl "1080p"
Assert-Test ($sel1080.AbsoluteUri -eq "https://alloha.cdn.net/vod/1080p/index.m3u8") "Complex master with AUDIO & SUBTITLES tags resolves 1080p"

$sel720 = Choose-MediaPlaylistUrl $complexMaster $cMasterUrl "720p"
Assert-Test ($sel720.AbsoluteUri -eq "https://alloha.cdn.net/vod/720p/index.m3u8") "Complex master resolves 720p"

Write-Host "`n=== TEST SUITE 13: All-AV1 Playlist Rejection / Edge Case ===" -ForegroundColor Cyan

$allAv1Master = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1920x1080,CODECS="av01.0.04M.08"
1080_av1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720,CODECS="av01.0.04M.08"
720_av1.m3u8
"@
$selAllAv1 = Choose-MediaPlaylistUrl $allAv1Master $cMasterUrl "1080p"
Assert-Test ($selAllAv1 -eq $null) "All-AV1 playlist returns null variant (no unplayable AV1 stream queued)"

Write-Host "`n=== TEST SUITE 14: Very Low Quality Fallback ===" -ForegroundColor Cyan

$only240pMaster = @"
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=426x240
240p.m3u8
"@
$sel240 = Choose-MediaPlaylistUrl $only240pMaster $cMasterUrl "1080p"
Assert-Test ($sel240.AbsoluteUri -eq "https://alloha.cdn.net/vod/240p.m3u8") "Title with only 240p available returns 240p for 1080p request"

Write-Host "`n=========================================="
Write-Host "Packaging & Stress Suite Total: $($global:passed + $global:failed)"
Write-Host "Passed: $global:passed" -ForegroundColor Green
Write-Host "Failed: $global:failed" -ForegroundColor $(if ($global:failed -gt 0) { "Red" } else { "Green" })
Write-Host "=========================================="

if ($global:failed -gt 0) { exit 1 } else { exit 0 }
