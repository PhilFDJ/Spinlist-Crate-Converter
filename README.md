# Spinlist Crate Converter

A small macOS app that converts `.m3u` / `.m3u8` playlists into Serato crates
(written to `~/Music/_Serato_/Subcrates`). Drag playlists onto the window or the
app icon.

## Building — two ways

### A) On GitHub (recommended — no local keychain hassle)

GitHub's macOS servers have a complete Apple certificate chain, so this avoids
the "unable to build chain to self-signed root" problems that can happen on a
local Mac. The workflow at `.github/workflows/build.yml` compiles, signs,
notarises, and attaches the finished `.dmg` to a GitHub release automatically.

**One-time setup — add these 5 repository secrets** (repo -> Settings -> Secrets
and variables -> Actions -> New repository secret). These are the SAME secrets you
already created for Music Manager and Gig Window:

| Secret | What it is |
|--------|------------|
| CSC_LINK | base64 of your Developer ID .p12 certificate |
| CSC_KEY_PASSWORD | the password you set on that .p12 |
| APPLE_ID | your Apple developer account email |
| APPLE_APP_SPECIFIC_PASSWORD | an app-specific password (account.apple.com) |
| APPLE_TEAM_ID | 3LVYMTC2X7 |

**To release:** Releases -> Draft a new release -> Choose a tag -> type v1.0.0 ->
"Create new tag: v1.0.0 on publish" -> Publish. The build runs automatically
(watch the Actions tab), and attaches Spinlist.Crate.Converter.dmg to the
release when done. Notarising can take a few minutes -- don't cancel.

The website download link expects the asset to be named exactly
Spinlist.Crate.Converter.dmg -- the workflow handles that.

### B) Locally on your Mac

See build.sh and notarize.sh. Requires Xcode command line tools, your
Developer ID set via export DEV_ID="...", and a complete local certificate
chain. If you hit "unable to build chain to self-signed root", use route A
instead.

## What's in this folder

```
.github/workflows/build.yml       - GitHub build/sign/notarise workflow (route A)
build.sh                          - local compile + sign + package (route B)
notarize.sh                       - local notarise + staple (route B)
src/SpinlistCrateConverter.swift  - the app source code
assets/Info.plist                 - app bundle configuration
assets/AppIcon.icns               - app icon (add your own if not present)
assets/dropmark.png               - logo shown in the app (optional)
```

## Notes

- Crates are written to ~/Music/_Serato_/Subcrates. Quit Serato before
  converting, then reopen it to see the new crates.
- The app is Mac-only (native SwiftUI). There is no Windows version.
