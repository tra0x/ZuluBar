# Releasing

Release commands are maintainer-only. Ordinary source builds do not need Apple
Developer credentials, Sparkle signing keys, Cloudflare access, or notarization
credentials.

## Prerequisites

- Apple Developer ID signing identity in the local Keychain.
- Apple notarization credentials in `.signing.local.mk`.
- Sparkle Ed25519 private key available to Sparkle's `sign_update` tool, or
  `SPARKLE_ED_PRIVATE_KEY` exported in the environment.
- Wrangler authenticated with Cloudflare:
  - local: `wrangler login`
  - CI/token-based runs: export `CLOUDFLARE_API_TOKEN`
- Private R2 bucket configured for paid artifacts.

Copy `.signing.local.mk.example` to `.signing.local.mk` and fill in local
values. `.signing.local.mk` is gitignored.

## Commands

Run this before publishing to verify Wrangler can see the target R2 bucket:

```sh
make check-release-auth
```

Build, sign, notarize, staple, create the Sparkle ZIP, sign it, upload it to
private R2, and write deployment metadata:

```sh
make publish-update NOTES="Initial v1.0.0 release."
```

If the app has already been built, notarized, and stapled, publish the existing
artifact without rebuilding:

```sh
make publish-update-from-current NOTES="Initial v1.0.0 release."
```

The publish command writes `dist/zulubar-site-release-vars.env`. Apply those
values to the deployment site's production Worker config so its keyed Sparkle
appcast serves the uploaded ZIP through private `/updates/download` URLs.

`dist/zulubar-site-release-vars.env` is generated release metadata and should
not be committed.
