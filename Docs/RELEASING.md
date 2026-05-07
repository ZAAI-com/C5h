# Releasing C5h

This doc covers how to cut a signed, notarized, universal-binary macOS release and
ship it through the Homebrew tap.

## Prerequisites (one-time setup)

### 1. Apple Developer account

You need an **Apple Developer Program** membership ($99/year) for code signing and
notarization. Without these, macOS 13+ shows a scary Gatekeeper dialog on first
launch.

### 2. Create a "Developer ID Application" certificate

1. Open **Keychain Access** on macOS.
2. Menu: **Keychain Access → Certificate Assistant → Request a Certificate From a
   Certificate Authority**.
3. Fill in your email + name, choose **"Saved to disk"**, click Continue.
4. Log in to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates).
5. Click **+**, choose **"Developer ID Application"**, upload the CSR from step 3.
6. Download the `.cer`, double-click to install into Keychain Access.

### 3. Export the certificate as a `.p12`

In Keychain Access:

1. Find **"Developer ID Application: YOUR NAME (TEAMID)"** under **My Certificates**.
2. Right-click → **Export**, pick format `.p12`, set a strong password, save.

### 4. Encode the `.p12` as base64 for GitHub Secrets

```bash
base64 -i cert.p12 -o cert.p12.b64
pbcopy < cert.p12.b64   # copies the base64 text to clipboard
```

### 5. Create an app-specific password

1. Go to [appleid.apple.com/account/manage](https://appleid.apple.com/account/manage).
2. Sign-In and Security → **App-Specific Passwords** → Generate a password.
3. Label it something like "C5h notarization" and copy the password.

### 6. Find your Team ID

1. [developer.apple.com/account](https://developer.apple.com/account).
2. Top-right → **Membership details** → **Team ID** (10-char alphanumeric).

## GitHub Secrets

Add these to **Settings → Secrets and variables → Actions** on the repo:

| Secret                        | Value                                                               |
| ----------------------------- | ------------------------------------------------------------------- |
| `APPLE_CERTIFICATE`           | Contents of `cert.p12.b64` from step 4                              |
| `APPLE_CERTIFICATE_PASSWORD`  | The `.p12` password from step 3                                     |
| `APPLE_SIGNING_IDENTITY`      | `Developer ID Application: YOUR NAME (TEAMID)` — the exact common name |
| `APPLE_ID`                    | Your Apple ID email address                                         |
| `APPLE_PASSWORD`              | The app-specific password from step 5                               |
| `APPLE_TEAM_ID`               | Your team ID from step 6                                            |

## `tauri.conf.json`

Add a `signingIdentity` under `bundle.macOS` to match `APPLE_SIGNING_IDENTITY`:

```json
"macOS": {
  "minimumSystemVersion": "12.0",
  "signingIdentity": "Developer ID Application: YOUR NAME (TEAMID)",
  "entitlements": "entitlements.plist"
}
```

Then create `src-tauri/entitlements.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-jit</key>
  <true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <true/>
</dict>
</plist>
```

> Note: Do not commit the actual identity string if the repo is public — use the secret.

## Cutting a release

```bash
# 1. Bump version in src-tauri/tauri.conf.json and package.json
# 2. Commit and push the release commit
git commit -am "Release v0.3.0"
git push
```

Then dispatch `.github/workflows/release.yml` manually with `version=0.3.0`.
The workflow now validates that `package.json`, `src-tauri/tauri.conf.json`, and the
requested workflow input all match before any build starts.

The `release.yml` workflow then:

1. Builds aarch64 and x86_64 in parallel.
2. Signs + notarizes each (if Apple secrets are set).
3. Fuses them into a universal binary (`universal` job).
4. Creates a draft GitHub Release tagged `v0.3.0` with DMGs attached.

Review the draft release on GitHub and publish when ready.

## Homebrew tap

Tap repo: `github.com/ZAAI-com/homebrew-tap`. Cask template lives at
`distribution/homebrew/c5h.rb`.

`.github/workflows/release-tap.yml` runs automatically when a Release is
published — it downloads the universal DMG, computes SHA256, renders the
template, and pushes to the tap. Required secret on this repo:
`HOMEBREW_TAP_REPO_COMMIT_TOKEN` (fine-grained PAT with Contents: read+write
on the tap repo).

A user can then install with:

```bash
brew install --cask zaai-com/tap/c5h
```

(Homebrew strips the `homebrew-` prefix when resolving tap names, so
`ZAAI-com/homebrew-tap` → `zaai-com/tap`.)

If the workflow ever fails, the manual fallback is: compute the SHA256
yourself (`shasum -a 256 C5h_0.3.0_universal.dmg`), copy
`distribution/homebrew/c5h.rb` into the tap repo's `Casks/c5h.rb`, replace
the two placeholders, commit + push.

## Troubleshooting

- **"The application can't be opened" on first launch**: signing/notarization
  failed. Check the release workflow logs for `xcrun notarytool` errors.
- **DMG opens but app crashes on launch**: likely an entitlements issue. Run
  `codesign --display --entitlements - C5h.app` on a local build to inspect.
- **Universal binary is too large**: you can reduce DMG size with `ditto --hfsCompression`
  in the `universal` job, but it's usually unnecessary — universal is ~2× arch-specific.
