# NeoMovies AltStore Installation

## What is AltStore?

AltStore is a sideloading app for iOS that allows you to install unsigned apps (IPA files) on your iPhone/iPad without jailbreak. It automatically refreshes app signatures every 7 days.

## Prerequisites

- iPhone/iPad running iOS 14.0 or later
- AltStore installed ([Download here](https://altstore.io/))
- Computer with AltServer running (for initial setup)

## Installation Methods

### Method 1: Add NeoMovies Source (Recommended - Auto-updates)

1. Open **AltStore** on your device
2. Tap **Browse** → **Sources** → **+** (top right)
3. Enter this URL:
   ```
   https://git.disroot.org/Neo/neomovies-mobile/raw/branch/main/altstore-source.json
   ```
4. Tap **Add**
5. Go to **Browse** → **NeoMovies** → **Install**
6. AltStore will automatically check for updates when refreshing apps (every 7 days)

### Method 2: Manual IPA Installation

1. Download the latest IPA from [GitHub Releases](https://github.com/Neo-Open-Source/neomovies-mobile/releases)
   - For stable releases: `neomovies-ios-unsigned-release-*.ipa`
   - For pre-releases: `neomovies-ios-unsigned-prerelease-*.ipa`
2. Open the IPA file on your device
3. Select **Open in AltStore**
4. AltStore will sign and install the app

## Updating the App

### If you added the Source (Method 1):
- Open AltStore → **My Apps**
- Pull down to refresh
- If an update is available, tap **Update** next to NeoMovies

### If you installed manually (Method 2):
- Download the new IPA from GitHub Releases
- Install it the same way (it will replace the old version)

## Keeping the App Active

AltStore apps expire after 7 days due to Apple's free developer certificate limitations. To keep NeoMovies working:

1. Connect your device to the same Wi-Fi as your computer running AltServer
2. Open AltStore → **My Apps**
3. Pull down to refresh
4. AltStore will automatically re-sign all apps

**Tip:** Enable **Background Refresh** for AltStore in iOS Settings to allow automatic refreshing.

## Troubleshooting

### "Unable to Install"
- Make sure AltServer is running on your computer
- Check that your device and computer are on the same Wi-Fi network
- Try restarting AltStore and AltServer

### "App Expired"
- Open AltStore and refresh your apps
- If AltServer is not available, you'll need to reinstall the app

### Source Not Loading
- Check your internet connection
- Verify the source URL is correct
- Try removing and re-adding the source

## Features

- ✅ Alloha and Collaps streaming sources
- ✅ HLS streaming with quality selection
- ✅ Multiple voiceovers and subtitles
- ✅ Episode switching in player
- ✅ Continue watching
- ✅ Multi-language support (EN, RU, UK, BE, RO)

## Support

- GitHub Issues: [Report a bug](https://github.com/Neo-Open-Source/neomovies-mobile/issues)
- Telegram: [Join community](https://t.me/neomovies)

## Notes

- This is an **unsigned** IPA for sideloading only
- Not available on the App Store
- Requires AltStore or similar sideloading tool
- Pre-release versions may contain bugs

---

**Made with ❤️  by Neo Open Source**
