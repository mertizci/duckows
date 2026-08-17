# Release & Distribution

The maintainer runbook. It is committed on purpose: it contains no secret
*values*, and the identities it names are already readable from any shipped
binary with `codesign -dv --verbose=4 /Applications/Duckows.app`. A runbook that
exists on one Mac is a runbook you lose with that Mac.

**Never paste into this file:** an app-specific password, the `.p12` password, a
PAT, or base64 certificate data.

## 1. Pipeline

```
gh release create vX.Y.Z
        │
        ▼
.github/workflows/release.yml  (on release: published, macos-15)
        │  import Developer ID cert into an ephemeral keychain
        ▼
scripts/release.sh "${GITHUB_REF_NAME#v}"
        │  xcodegen → xcodebuild archive (Manual signing, hardened runtime)
        │  copy .app out of the xcarchive  →  verify  →  assert designated requirement
        │  zip → notarize → staple → RE-ZIP
        │  create-dmg → sign → notarize → staple
        ▼
gh release upload  (Duckows-X.Y.Z.zip + Duckows-X.Y.Z.dmg)
        ▼
clone mertizci/homebrew-tap → sed-bump Casks/duckows.rb → push
```

Two artifacts, two consumers:

| Artifact | Consumed by |
| --- | --- |
| `Duckows-X.Y.Z.zip` | The Homebrew cask (`url` + `sha256`) |
| `Duckows-X.Y.Z.dmg` | Manual download **and the in-app updater** |

**The DMG is not optional.** `UpdateController` only offers a release that has
one; publish without it and every installed copy silently reports "up to date".

## 2. Identities

| Item | Value |
| --- | --- |
| Developer ID Application | `Developer ID Application: MERT IZCI (NZDMMFNMU4)` |
| Team ID | `NZDMMFNMU4` |
| Bundle identifier | `com.duckows.app` |
| Minimum macOS | 14.0 |
| App repo | `mertizci/duckows` |
| Tap repo | `mertizci/homebrew-tap` |
| Cask file | `Casks/duckows.rb` |

The designated requirement, enforced in three places (`UpdateInstaller`,
`scripts/release.sh`, and implicitly by macOS TCC):

```
identifier "com.duckows.app" and anchor apple generic and certificate leaf[subject.OU] = "NZDMMFNMU4"
```

## 3. GitHub Actions secrets

Repository: `mertizci/duckows`. Names only — values live in GitHub.

| Secret | Purpose |
| --- | --- |
| `APPLE_ID` | Apple ID for `notarytool` |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |
| `APPLE_TEAM_ID` | `NZDMMFNMU4` |
| `DEVELOPER_ID_CERT_P12_BASE64` | Base64 of the **legacy-format** `.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | Password for that `.p12` |
| `KEYCHAIN_PASSWORD` | Throwaway password for the ephemeral CI keychain |
| `TAP_GITHUB_TOKEN` | Fine-grained PAT that can push to the tap |

Set them with stdin so nothing lands in shell history:

```bash
R=mertizci/duckows
gh secret set APPLE_ID --repo "$R"
gh secret set APPLE_APP_PASSWORD --repo "$R"
printf 'NZDMMFNMU4' | gh secret set APPLE_TEAM_ID --repo "$R"
openssl rand -hex 32 | tr -d '\n' | gh secret set KEYCHAIN_PASSWORD --repo "$R"
gh secret set TAP_GITHUB_TOKEN --repo "$R"
```

## 4. Regenerating the certificate secret

macOS `security import` **cannot read an OpenSSL 3 PKCS#12**. A modern `.p12`
fails in CI with `MAC verification failed during PKCS12 import`. Rebuild it with
`-legacy`:

```bash
cd /tmp
P1=$(openssl rand -hex 16)

# 1. Export all identities (approve the macOS prompt).
security export -k ~/Library/Keychains/login.keychain-db -t identities \
  -f pkcs12 -P "$P1" -o all.p12
openssl pkcs12 -legacy -in all.p12 -passin pass:"$P1" -nodes -out all.pem

# 2. Isolate only the Developer ID cert and its matching key, by localKeyID.
python3 - <<'PY'
import re
pem = open('/tmp/all.pem').read()
blocks = re.findall(r'(friendlyName:.*?localKeyID:[^\n]*\n)(.*?-----END (?:CERTIFICATE|PRIVATE KEY)-----\n)', pem, re.S)
target = cert = key = None
for h, b in blocks:
    fn = re.search(r'friendlyName:\s*(.*)', h).group(1).strip()
    kid = re.search(r'localKeyID:\s*([0-9A-Fa-f ]+)', h).group(1).strip()
    if 'CERTIFICATE' in b and fn.startswith('Developer ID Application'):
        target = kid
        cert = re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\n', b, re.S).group(0)
for h, b in blocks:
    kid = re.search(r'localKeyID:\s*([0-9A-Fa-f ]+)', h).group(1).strip()
    if 'PRIVATE KEY' in b and kid == target:
        key = re.search(r'-----BEGIN PRIVATE KEY-----.*?-----END PRIVATE KEY-----\n', b, re.S).group(0)
open('/tmp/devid_cert.pem', 'w').write(cert)
open('/tmp/devid_key.pem', 'w').write(key)
PY

# 3. Rebuild as a legacy .p12.
P2=$(openssl rand -hex 20)
openssl pkcs12 -export -legacy \
  -inkey /tmp/devid_key.pem -in /tmp/devid_cert.pem \
  -name "Developer ID Application: MERT IZCI (NZDMMFNMU4)" \
  -out /tmp/devid.p12 -passout pass:"$P2"

# 4. Push both secrets.
base64 -i /tmp/devid.p12 | gh secret set DEVELOPER_ID_CERT_P12_BASE64 --repo mertizci/duckows
printf '%s' "$P2"        | gh secret set DEVELOPER_ID_CERT_PASSWORD   --repo mertizci/duckows

# 5. Clean up.
rm -f /tmp/all.p12 /tmp/all.pem /tmp/devid_cert.pem /tmp/devid_key.pem /tmp/devid.p12
```

## 5. Notary credentials for local runs

```bash
xcrun notarytool store-credentials duckows-notary \
  --apple-id "you@example.com" --team-id "NZDMMFNMU4" --password "app-specific-password"
```

## 6. Tap PAT

`GITHUB_TOKEN` cannot push to another repository, hence `TAP_GITHUB_TOKEN`.
Create a fine-grained PAT at
<https://github.com/settings/personal-access-tokens/new>:

- Resource owner: `mertizci`
- Repository access: only `mertizci/homebrew-tap`
- Repository permissions → **Contents: Read and write**

## 7. Cutting a release

```bash
gh release create vX.Y.Z --target main --title "vX.Y.Z" --notes "..."
gh run watch "$(gh run list --workflow Release --limit 1 --json databaseId --jq '.[0].databaseId')"
```

## 8. Local release without CI

```bash
brew install create-dmg
scripts/release.sh X.Y.Z
```

Then create the release manually and bump the cask by hand.

## 9. Rules specific to this app

- **Never change the bundle identifier, and never sign with a different team.**
  Either one breaks the updater in every installed copy *and* resets every
  user's Accessibility and Screen Recording grants. Renewing the certificate is
  safe: `subject.OU` does not change.
- **Always ship a `.dmg`.** No DMG, no updates.
- **Always test the updater from a real older build** before announcing.
- `project.yml` pins `MARKETING_VERSION` to `0.0.0` on purpose. CI overrides it
  from the tag, and `UpdateController` skips the launch check for `0.0.0` so dev
  builds do not nag. Force it with
  `defaults write com.duckows.app Duckows.forceUpdateCheck -bool YES`.

## 10. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `MAC verification failed during PKCS12 import` | Modern OpenSSL 3 `.p12` | Rebuild with `openssl pkcs12 -export -legacy` (§4) |
| `future Xcode project file format` | Runner Xcode older than the one that generated the project | The workflow selects the newest `Xcode_*.app`; bump the runner image |
| `Permission to ...homebrew-tap denied (403)` | `TAP_GITHUB_TOKEN` lacks write | Fine-grained PAT, Contents: Read and write (§6) |
| Notarization returns `Invalid` | Missing hardened runtime or timestamp | `release.sh` passes `--options runtime --timestamp`; check the signing step |
| Cask bump step succeeds but changes nothing | The `sed` anchors on two-space indentation | The workflow's `grep -q` assertion now fails loudly instead |
| Update downloads but the app never comes back | Swap script failed | It stages and renames, so the old bundle rolls back; check `~/Library/Logs` and rerun `open /Applications/Duckows.app` |
| Login item refuses with `kSMErrorInvalidSignature` | App Translocation | Move Duckows to `/Applications` |

## 11. Files

| Path | Role |
| --- | --- |
| `project.yml` | XcodeGen source of truth; `.xcodeproj` is generated and gitignored |
| `scripts/release.sh` | The whole build/sign/notarize/package pipeline |
| `scripts/make-app-icon.swift` | Regenerates the app icon PNG set |
| `.github/workflows/ci.yml` | Build + test on every push and PR |
| `.github/workflows/release.yml` | The release job |
| `Duckows/Update/` | The in-app updater |
| `mertizci/homebrew-tap` → `Casks/duckows.rb` | The cask; the tap is the single source of truth |
