# t.

An independent Telegram client for iPhone and iPad, with flexible chat organization, themes, translation and privacy controls.

The upstream source snapshot is `db0722d6`, imported on 2026-10-11. Upstream copyrights and license notices remain applicable.

- App name and icon: **t.**
- Bundle ID: `${BUNDLE_ID}`
- Telegram API identity: private `APP_ID` and `APP_HASH` values
- App Store Connect identity: private `ASC_APP_ID` value; primary language English (Canada)
- Branch: `master`

There is one client identity. Compatibility variants and other clients' API credentials are not used. All app identifiers and API credentials are loaded from the ignored local `.env` and matching GitHub Actions secrets, never from committed values.

## Features

- Ghost mode with separate read-receipt, typing/upload and online-status controls, including media and story viewing. Optional offline sending delays cloud delivery by 15 seconds after uploads; manual schedules are preserved.
- Retained deleted messages, edit history, preservation filters and local archive import/export.
- Keep locally loaded chats after leaving or being kicked.
- Optional screenshots in secret chats and an Expire button for TTL photos and videos.
- Local message filters and sponsored-message hiding.
- Separate styles and colors for edited/deleted markers, plus custom edited text.
- Local Premium interface options; server features still require a real subscription.
- Native simulator support.

Builds use your own private API registration.

## Build and distribution

GitHub Actions builds a signed arm64 App Store IPA with Share, Notification Content, Notification Service, Siri, Widget, and Broadcast Upload extensions, then uploads it to App Store Connect. See [CI setup](docs/tdot-ci.md) for signing requirements and [build notes](docs/build.md) for Bazel and Xcode details.

## App Store information

The primary listing is English (Canada). The [t. Privacy Policy](https://docs.kitta.co/tdot/) is hosted on Kitta Docs in the separate `tdot` section. Its source is maintained in [kitta-co/privacy-policy](https://github.com/kitta-co/privacy-policy). Support site source is in `AppStore/site`; deploy it to the configured Cloudflare Pages project.

## License and attribution

This project preserves upstream licenses and copyright notices in the source. Telegram is a trademark of Telegram Messenger Inc. t. is an independent client and is not endorsed by Telegram.
