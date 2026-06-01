<img src=".github/assets/rights-banner.svg" alt="Trans Rights are Human Rights banner" width="100%" />

<div align="center">

<img src=".github/assets/logo.png" width="120" height="120" style="border-radius: 24px;" />

# NeoMovies

### Movies & series streaming client for mobile

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/Neo-Open-Source/neomovies-mobile?color=black&label=Stable&logo=github)](https://github.com/Neo-Open-Source/neomovies-mobile/releases/latest/)
[![GitHub release (latest by date including pre-releases)](https://img.shields.io/github/v/release/Neo-Open-Source/neomovies-mobile?include_prereleases&label=Preview&logo=github)](https://github.com/Neo-Open-Source/neomovies-mobile/releases/)
[![GitHub all releases](https://img.shields.io/github/downloads/Neo-Open-Source/neomovies-mobile/total?label=Downloads&logo=github)](https://github.com/Neo-Open-Source/neomovies-mobile/releases/latest/)
[![Telegram](https://img.shields.io/badge/Telegram-NeoOpenSource-blue?style=flat&logo=telegram)](https://t.me/neomovies_news)

Cross-platform streaming client built with Expo/React Native for iOS and Android.

</div>

## Features

- 🎬 **Multiple Sources** — Alloha and Collaps streaming providers
- 🎥 **HLS Streaming** — Adaptive quality with manual selection
- 🎙️ **Voiceovers & Subtitles** — Multiple audio tracks and subtitle support
- ⏭️ **Episode Switching** — Navigate between episodes in player
- 📱 **Continue Watching** — Resume from where you left off
- 🌍 **Multi-language** — English, Russian, Ukrainian, Belarusian, Romanian
- 🎨 **Native UI** — Custom design for iOS and Android

## Download

### Android
- **Stable:** [Latest Release](https://github.com/Neo-Open-Source/neomovies-mobile/releases/latest)
- **Preview:** [Pre-releases](https://github.com/Neo-Open-Source/neomovies-mobile/releases)

### iOS (AltStore)
- **Installation Guide:** [ALTSTORE.md](ALTSTORE.md)
- Add source to AltStore:
  ```
  https://git.disroot.org/Neo/neomovies-mobile/raw/branch/main/altstore-source.json
  ```

## Development

### Prerequisites
- Node.js 20+
- pnpm 9+
- Expo CLI
- For iOS: Xcode 16.2+
- For Android: Android Studio with SDK 34+

### Setup
```bash
# Clone repository
git clone https://github.com/Neo-Open-Source/neomovies-mobile.git
cd neomovies-mobile

# Install dependencies
pnpm install

# Copy environment variables
cp .env.example .env

# Start development server
pnpm start
```

### Environment Variables
- `EXPO_PUBLIC_API_BASE_URL` — NeoMovies API base URL (default: `https://api.neomovies.ru/api/v1`)
- `EXPO_PUBLIC_NEO_ID_BASE_URL` — Neo ID OAuth URL (default: `https://id.neomovies.ru`)

### Build

#### Android
```bash
# Local build
eas build --platform android --profile preview --local

# Production build
eas build --platform android --profile production
```

#### iOS
```bash
# Simulator build
eas build --platform ios --profile preview --local

# Production build (requires Apple Developer account)
eas build --platform ios --profile production
```

## Architecture

- **Framework:** Expo SDK 55 / React Native 0.83
- **Navigation:** Expo Router (file-based routing)
- **State:** React Query for server state
- **Styling:** Custom theme system with dark mode
- **Native Modules:** 
  - `neomovies-core` (Swift/Kotlin) — Video player, HLS proxy, Alloha parser
  - Expo Modules API for native bridge

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting PRs.

## Community

- **Telegram:** [@neomovies_news](https://t.me/neomovies_news)
- **Website:** [neomovies.ru](https://www.neomovies.ru)
- **Issues:** [GitHub Issues](https://github.com/Neo-Open-Source/neomovies-mobile/issues)

## License

Apache 2.0: See [LICENSE](LICENSE).

---

<div align="center">

**Made with ❤️ by Neo Open Source**

</div>
