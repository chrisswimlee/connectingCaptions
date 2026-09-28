# Homebrew listing

Personal tap files live in a separate `homebrew-connectingcaptions` repo, not this git tree. Official listing is a later PR to `homebrew/cask`. FluidVoice already owns `brew install --cask fluidvoice`.

## Todo

1. `gh auth login`
2. `./scripts/enable-github-gates.sh` so `chrisswimlee/connectingCaptions` is public
3. `./build.sh release` with Developer ID and notarization credentials
4. Put the published team ID in `ConnectingCaptionsProduct.allowedUpdateTeamIDs`
5. Tag `v1.6.12` (must match `CFBundleShortVersionString`) so `.github/workflows/release.yml` attaches `Connecting-Captions-1.6.12.zip` and `SHA256SUMS`
6. From the tap checkout: `./update-cask.sh 1.6.12 /path/to/connectingCaptions/dist/SHA256SUMS`
7. Publish the tap:

```bash
cd /path/to/homebrew-connectingcaptions
git add Casks/connectingcaptions.rb README.md update-cask.sh .gitignore
git commit -m "Add connectingcaptions cask."
gh repo create chrisswimlee/homebrew-connectingcaptions --public --source=. --remote=origin --push
```

8. Verify:

```bash
brew tap chrisswimlee/connectingcaptions
brew install --cask connectingcaptions
# Open Theater, allow the microphone, Listen one sentence
brew uninstall --cask connectingcaptions
```

9. After one launch, refresh zap paths with `brew generate-zap --cask connectingcaptions` and commit any extras (do not zap FluidVoice or FluidAudio)
10. Add `brew tap chrisswimlee/connectingcaptions && brew install --cask connectingcaptions` to the app README Install section
11. After roughly 75 GitHub stars, PR `chrisswimlee-connectingcaptions` to [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) with a pinned `sha256` (not `:no_check`). Commit message: `chrisswimlee-connectingcaptions 1.6.12 (new cask)`
