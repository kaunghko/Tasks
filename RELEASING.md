# Releasing Tasks

Updates use [Sparkle](https://sparkle-project.org), the app's only dependency. A release is a notarized zip attached to a GitHub Release. [`appcast.xml`](appcast.xml) on `main` is the feed installed copies check. Each entry in it is signed with an EdDSA key, and the app only installs an update if the signature matches the public key in `Tasks-Info.plist`.

One-time setup on the release Mac:

1. Xcode ▸ Settings ▸ Accounts: sign in with the Apple ID for team `A9AR4SKF2Z`. The release script asks Xcode to create the Developer ID certificate the first time.
2. Create an app-specific password at [account.apple.com](https://account.apple.com) ▸ Sign-In and Security, then save it in the Keychain:
   ```sh
   xcrun notarytool store-credentials TasksNotary --apple-id <apple-id> --team-id A9AR4SKF2Z
   ```
3. `brew install gh && gh auth login`
4. The Sparkle private key is in the login Keychain as "Private key for signing Sparkle updates". Back it up somewhere safe. If you lose it, installed copies can't be updated:
   ```sh
   build/sparkle-2.10.0/bin/generate_keys -x ~/sparkle-private-key   # keep this file out of the repo
   ```
   On a new Mac, import it with `generate_keys -f <file>`.

Then each release is one command from a clean `main`:

```sh
scripts/release.sh 0.2.0
```

The script:
- runs the tests
- bumps the version and build number
- archives the app, signs it with Developer ID, notarizes it and staples the ticket
- zips the app and signs the zip into `appcast.xml`
- tags the commit, uploads the GitHub Release, and pushes `main`
