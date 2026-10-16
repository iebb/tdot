# Nagram upstream and the t. overlay

The canonical app base is [NextAlone/Nagram-iOS](https://github.com/NextAlone/Nagram-iOS), currently `fb030aa9951078c1c48e0d1a8c19055859f3d21b`. `versions.json` records the revision. The initial imported snapshot was `db0722d6`.

t. keeps its independent branding, private API and signing configuration, App Store metadata, CI, and these Ayu features on top:

- Configurable Ghost Mode for read, typing/upload and online activity, with optional delayed cloud sending.
- Local preservation of deleted and edited messages, preservation rules, and history import/export.
- Locally loaded chats after leaving or being kicked.
- Optional secret-chat screenshots and local expiration of TTL media.
- Message filters, ad hiding, edited/deleted markers, and local Premium UI and limits.

AyuSync remains deferred. Screenshot notifications remain enabled; local Premium does not grant server subscription features.

Unrelated app behavior follows Nagram. UID-based developer/sponsor badges are removed, including their lookup lists, views, tooltips and localization. Keep this explicit downstream exception when syncing Nagram. The extra settings use t.’s native category menu and focused pages, with shared Nagram controls and preference keys. Keep this user-requested layout when syncing; existing setting links and search must still reach the right row. Startup, app navigation outside these extra settings, and notification behavior follow Nagram; the original fork’s About screen, agreement prompt, settings redesign and notification-test hooks remain removed. The original fork's combined chat filters, custom sorting, music controls, default text formatting, contact defaults, background-location notification fallback and extra account limits are removed. The app uses its signed notification service extension and normal APNs registration.

For every update, apply the changes after the recorded Nagram revision onto `master`, preserve this overlay and private configuration, and review overlaps. Keep the README's source attribution current without adding the former product name or restoring its removed feature list. Run a full app build with all six signed extensions before accepting a release. Never merge upstream commit history into the reset public history or publish a compiled app, clear compiler cache, identifiers or credentials as a public artifact.
