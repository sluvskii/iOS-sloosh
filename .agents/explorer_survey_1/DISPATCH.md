## 2026-08-25T00:54:29Z
Investigate the existing Messenger UI and Navigation architecture in Sloosh iOS (W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\UI\Messenger\, ContentView.swift, and related UI files).

Specific areas to investigate:
1. Current MessengerView.swift structure: top navigation bar, right-side buttons (e.g. square.and.pencil), search bar implementation, chat list presentation, and navigation destinations.
2. Existing UI components, Liquid Glass modifiers used (.glassEffect()), color styling, and adherence to iOS 26+ guidelines (no .ultraThinMaterial).
3. How MessengerView manages chat items, unread badges, timestamps, avatars, and interactions.
4. What UI changes and additions are needed to support:
   - R1: Top-right Liquid Glass Action Menu ("Создать канал", "Создать беседу" coming soon) & Channel Creation Sheet (name, description, avatar/emoji/accent color).
   - R2: Channel feed view (ChannelDetailView), role separation (Owner broadcasting bar vs Subscriber read-only stream + banner), emoji reactions, pinned post bar (PinnedPostBar), rich media cards.
   - R3: Channel list item in MessengerView with 📢 badge, search results section for public channels ("КАНАЛЫ") with quick subscribe button, and ChannelInfoView.
