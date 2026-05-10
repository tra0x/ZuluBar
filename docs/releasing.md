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

Build, sign, notarize, staple, create the first-download DMG, and upload it to
private R2:

```sh
make publish-download
```

Build, sign, notarize, staple, create the Sparkle ZIP, sign it, upload it to
private R2, and write deployment metadata:

```sh
make publish-update NOTES="Initial v1.0.0 release."
```

If the app has already been built, notarized, and stapled, publish the existing
first-download DMG without rebuilding:

```sh
make publish-download-from-current
```

Archive and upload the matching app symbols privately:

```sh
make publish-symbols-from-current
```

If the app has already been built, notarized, and stapled, publish the existing
Sparkle update ZIP without rebuilding:

```sh
make publish-update-from-current NOTES="Initial v1.0.0 release."
```

The publish command writes `dist/zulubar-site-release-vars.env`. Apply those
values to the deployment site's production Worker config so its keyed Sparkle
appcast serves the uploaded ZIP through private `/updates/download` URLs.

`dist/zulubar-site-release-vars.env` is generated release metadata and should
not be committed.

## Symbols

Keep the `.dSYM` for every shipped build. It must come from the same build that
produced the distributed app, otherwise crash reports will not symbolicate
correctly.

`make publish-symbols-from-current` archives:

```text
build/Release-Paid/ZuluBar.app.dSYM
```

and uploads it to private R2 under:

```text
symbols/ZuluBar-<version>.dSYM.zip
```

Symbols are maintainer-only diagnostic artifacts. They should not be committed
to git or exposed through customer download routes.

## Tags

Use annotated tags for releases:

```sh
git tag -a v1.0.0 -m "ZuluBar 1.0.0"
git push origin v1.0.0
```

Signed annotated tags are preferred when the maintainer has working Git tag
signing configured:

```sh
git tag -s v1.0.0 -m "ZuluBar 1.0.0"
git push origin v1.0.0
```

The tag message should include the product name and version. Do not include
private artifact URLs, credentials, customer keys, notarization passwords, or
other release secrets in the tag annotation.
