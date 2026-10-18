# t. CI and TestFlight

The only shipping identity is `${BUNDLE_ID}`, Telegram API ID `${APP_ID}`, and the `t.` icon. All six app extensions remain enabled in distribution builds. The shared App Group is `group.${BUNDLE_ID}`.

GitHub Actions uses Xcode 27 and the upstream Bazel wrapper. A push to `master` produces and uploads a signed release IPA to TestFlight. Dispatch **Build t. and upload to TestFlight** with distribution **simulator** when a simulator artifact is needed. Build numbers come from the workflow run number plus the private `BUILD_NUMBER_OFFSET` used to preserve Apple build numbering across repository migration. Upload does not mean processing or review has completed: CI queries the exact processed build and then adds it to the internal TestFlight group.

Required GitHub secrets (the same identifiers are stored in the ignored local `.env`):

- `APP_ID`, `BUNDLE_ID`, `TEAM_ID`, `APP_GROUP_ID`, `APP_URL_SCHEME`, `ASC_APP_ID`: app and signing identifiers.

- `CI_CACHE_KEY`: random private encryption key for the compiled Bazel cache.
- `APP_HASH`: the Telegram API hash matching the app's API ID.
- `OPENROUTER_API_KEY`: private key for the daily free-model source merge and review. It is stored in the ignored `.env` for operator access; scheduled sync runs entirely on GitHub Actions.
- `IOS_SIGNING_CERTIFICATE_P12`: base64 Kitta distribution certificate and private key.
- `IOS_SIGNING_CERTIFICATE_PASSWORD`: the P12 password.
- `IOS_PROVISIONING_PROFILES_TAR_GZ`: base64 gzip-compressed tar archive containing seven App Store profiles, each assigned to `group.${BUNDLE_ID}`, using the same distribution certificate. The main app also requires Push Notifications and Siri; the Intents extension requires Siri.
- `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY`: the Kitta App Store Connect API key.

`ASC_APP_ID` is a repository secret; the App Store primary locale is `en-CA`. Signing keys and profiles are imported into an ephemeral keychain and deleted after every job. Build configuration is generated under ignored `build-input/`; the API hash never appears in committed examples.

The IPA is checked before upload for the exact bundle, display name, version, build, team, distribution profiles, App Group, production APNs entitlement, and complete extension list. Internal TestFlight, external Beta App Review, and App Store review are separate states. External testing additionally needs beta review metadata and Apple approval. App Store review needs listing metadata, screenshots, privacy declarations, age rating, and review information.

Push notifications also require the matching APNs credentials configured for this API application in Telegram's provider settings. Apple provisioning alone does not establish delivery through Telegram.

Compiled IPAs and symbols are not published as GitHub artifacts because they contain the app identifiers. TestFlight receives the signed IPA directly. CI retains only a status report without app identifiers. Simulator builds can be exported locally using the ignored `.env`.

Compiler caches are encrypted and authenticated before GitHub retention. A private repository can migrate an older cache during setup; public runs never restore legacy plaintext caches.
