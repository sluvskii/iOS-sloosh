# Contributing to NeoMovies Mobile

Thank you for your interest in contributing to NeoMovies! We welcome contributions from everyone.

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive feedback
- Respect different viewpoints and experiences

## How to Contribute

### Reporting Bugs

Before creating a bug report:
1. Check if the bug has already been reported in [Issues](https://github.com/Neo-Open-Source/neomovies-mobile/issues)
2. Test with the latest version to see if the bug still exists

When creating a bug report, include:
- **Device & OS version** (e.g., iPhone 14 Pro, iOS 17.2)
- **App version** (found in Settings → About)
- **Steps to reproduce** the bug
- **Expected behavior** vs **actual behavior**
- **Screenshots or screen recordings** if applicable
- **Logs** if available (check Xcode Console or Android Logcat)

### Suggesting Features

Feature requests are welcome! Please:
1. Check if the feature has already been requested
2. Describe the problem you're trying to solve
3. Explain your proposed solution
4. Consider alternative solutions

### Pull Requests

#### Before You Start

1. **Check existing issues** — someone might already be working on it
2. **Open an issue first** for significant changes to discuss the approach
3. **Fork the repository** and create a branch from `main`

#### Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/neomovies-mobile.git
cd neomovies-mobile

# Install dependencies
pnpm install

# Copy environment variables
cp .env.example .env

# Start development server
pnpm start
```

**Requirements:**
- Node.js 20+
- pnpm 9+
- For iOS: macOS with Xcode 16.2+
- For Android: Android Studio with SDK 34+

#### Code Style

- **TypeScript** — use strict typing, avoid `any`
- **Formatting** — code is auto-formatted on commit (Prettier)
- **Naming conventions:**
  - Components: `PascalCase` (e.g., `MediaCard.tsx`)
  - Hooks: `camelCase` with `use` prefix (e.g., `useWatchProgress.ts`)
  - Utilities: `kebab-case` (e.g., `github-releases.ts`)
- **File structure:**
  ```
  src/
  ├── app/              # Expo Router screens
  ├── components/       # Reusable UI components
  ├── hooks/            # Custom React hooks
  ├── lib/              # Utilities and API clients
  ├── i18n/             # Translations
  └── styles/           # Style definitions
  ```

#### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>

[optional body]
```

**Types:**
- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation changes
- `style:` — formatting, missing semicolons, etc.
- `refactor:` — code restructuring without behavior change
- `perf:` — performance improvements
- `test:` — adding or updating tests
- `chore:` — maintenance tasks, dependencies

**Examples:**
```
feat: add GitHub releases update checker

fix: iOS progress resets when changing quality

docs: update AltStore installation guide

refactor: extract cache size calculation to utility
```

#### Pull Request Process

1. **Create a feature branch:**
   ```bash
   git checkout -b feat/your-feature-name
   ```

2. **Make your changes:**
   - Write clean, readable code
   - Add comments for complex logic
   - Update documentation if needed

3. **Test your changes:**
   - Test on both iOS and Android if possible
   - Verify existing features still work
   - Check for console errors/warnings

4. **Commit your changes:**
   ```bash
   git add .
   git commit -m "feat: add your feature"
   ```

5. **Push to your fork:**
   ```bash
   git push origin feat/your-feature-name
   ```

6. **Open a Pull Request:**
   - Use a clear, descriptive title
   - Reference related issues (e.g., "Fixes #123")
   - Describe what changed and why
   - Include screenshots/videos for UI changes
   - Mark as draft if work is in progress

#### PR Review Process

- Maintainers will review your PR within a few days
- Address feedback by pushing new commits
- Once approved, a maintainer will merge your PR
- Your contribution will be included in the next release!

## Translation Contributions

We support multiple languages: English, Russian, Ukrainian, Belarusian, Romanian.

To add or improve translations:

1. Edit files in `src/i18n/locales/`
2. Follow the existing structure
3. Test the app in your language
4. Submit a PR with your changes

**Adding a new language:**
1. Create `src/i18n/locales/[code].ts` (e.g., `de.ts` for German)
2. Add the locale to `src/i18n/types.ts`
3. Update `src/app/settings/language.tsx` to include the new language

## Native Module Development

NeoMovies uses native modules for video playback and streaming.

**iOS (Swift):**
- Located in `modules/neomovies-core/ios/`
- Uses Expo Modules API
- Test with Xcode simulator and real devices

**Android (Kotlin):**
- Located in `modules/neomovies-core/android/`
- Uses Expo Modules API
- Test with Android emulator and real devices

**Before modifying native code:**
1. Discuss the change in an issue first
2. Test thoroughly on both platforms
3. Document any new native APIs

## Questions?

- **Telegram:** [@neomovies_news](https://t.me/neomovies_news)
- **GitHub Issues:** [Ask a question](https://github.com/Neo-Open-Source/neomovies-mobile/issues/new)

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.

---

**Thank you for contributing to NeoMovies! ❤️**
