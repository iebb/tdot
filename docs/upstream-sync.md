# Nagram upstream and the t. overlay

The canonical app base is [NextAlone/Nagram-iOS](https://github.com/NextAlone/Nagram-iOS), currently `9faf62288045c4831442324f1fe327afa035e2ac`. `versions.json` records the revision. The initial imported snapshot was `db0722d6`.

t. keeps its independent branding, private API and signing configuration, App Store metadata, CI, and these Ayu features on top:

- Configurable Ghost Mode for read, typing/upload and online activity, with optional delayed cloud sending.
- Local preservation of deleted and edited messages, preservation rules, and history import/export.
- Locally loaded chats after leaving or being kicked.
- Optional secret-chat screenshots and local expiration of TTL media.
- Message filters, ad hiding, edited/deleted markers, and local Premium UI and limits.

AyuSync remains deferred. Screenshot notifications remain enabled; local Premium does not grant server subscription features.

Unrelated app behavior follows Nagram. UID-based developer/sponsor badges are removed, including their lookup lists, views, tooltips and localization. Keep this explicit downstream exception when syncing Nagram. The extra settings use t.’s native category menu and focused pages, with shared Nagram controls and preference keys. Keep this user-requested layout when syncing; existing setting links and search must still reach the right row. Startup, app navigation outside these extra settings, and notification behavior follow Nagram; the original fork’s About screen, agreement prompt, settings redesign and notification-test hooks remain removed. The original fork's combined chat filters, custom sorting, music controls, default text formatting, contact defaults, background-location notification fallback and extra account limits are removed. The app uses its signed notification service extension and normal APNs registration.

For every update, apply the changes after the recorded Nagram revision onto `master`, preserve this overlay and private configuration, and review overlaps. Keep the README's source attribution current without adding the former product name or restoring its removed feature list. Run a full app build with all six signed extensions before accepting a release. Never merge upstream commit history into the reset public history or publish a compiled app, clear compiler cache, identifiers or credentials as a public artifact.

## Daily hosted sync

`upstream-sync.yml` runs on GitHub Actions daily at 03:23 UTC (12:23 Japan time), with manual dry-run and live-model smoke-test options. The local Codex heartbeat is disabled. No local checkout or computer is needed for scheduled work.

`ci/sync-upstream.py` compares the recorded revision with upstream HEAD, applies a three-way snapshot merge, and asks OpenRouter's `openrouter/free` router to resolve overlapping text hunks and review all proposed source deltas. Prompt and completion price ceilings are both zero; there is no paid model fallback. Each run permits at most 18 model calls. A free-provider outage, quota limit, incomplete response or uncertain decision stops publication and leaves the pin unchanged for the next run. Only public source is sent to the model; it cannot execute commands or access signing credentials.

The model job has read-only repository access. A separate publisher validates allowed paths, credentials, existing settings/callbacks/category links, release configuration and concurrent master/upstream changes before creating one commit with only the existing public master as its parent. Upstream CI, scripts and documentation are excluded from the app snapshot. Other infrastructure, signing configuration, renames, binary overlaps, toolchain changes and oversized updates require manual review. README edits are preserved apart from the source revision. The publisher explicitly dispatches the signed build because pushes made with `GITHUB_TOKEN` do not trigger push workflows. An existing active release is preserved.

The daily job also resumes and audits the latest exact iOS TestFlight train, even without new upstream commits. It preserves pending beta review, verifies both audience attachments, checks the rendered public join page, and attaches the eligible build to the App Store version only while it is in Prepare for Submission. Signed CI performs the same external-beta continuation immediately after upload. No workflow publishes privacy declarations, submits an App Store review, invites individual testers or changes review credentials. Apple approval remains separate from upload success.
