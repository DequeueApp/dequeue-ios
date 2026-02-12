# TestFlight Deployment with Fastlane

This document describes the TestFlight deployment setup for Dequeue using Fastlane.

## Overview

Dequeue uses Fastlane to automate building, code signing, and uploading to TestFlight. This setup is based on the proven approach used in Minsa.

## Workflow

### Automatic Deploys
- **Trigger:** Every push to `main` that modifies `Dequeue/**` files
- **Runs:** GitHub Actions workflow `.github/workflows/testflight.yml`
- **Output:** New build uploaded to TestFlight for internal testing

### Manual Deploys
- **Trigger:** Workflow dispatch button in GitHub Actions
- **Use case:** Deploy without code changes (config updates, etc.)

## Required Secrets

All secrets must be configured in GitHub repository settings:

| Secret | Description | How to Get |
|--------|-------------|------------|
| `MATCH_DEPLOY_KEY` | SSH private key for certificates repo | Generate SSH key, add to certificates repo deploy keys |
| `MATCH_PASSWORD` | Password for Match certificate encryption | Generate secure password, store in 1Password |
| `MATCH_GIT_URL` | Git URL of certificates repo | `git@github.com:victorquinn/certificates.git` |
| `ASC_KEY_ID` | App Store Connect API Key ID | App Store Connect → Users & Access → Keys |
| `ASC_ISSUER_ID` | App Store Connect API Issuer ID | App Store Connect → Users & Access → Keys |
| `ASC_KEY_CONTENT` | App Store Connect API Key (base64) | Download `.p8` file, encode: `base64 < AuthKey_XXX.p8` |
| `ITC_TEAM_ID` | iTunes Connect Team ID | App Store Connect → Account settings |

### Setting Up Match (First Time)

Match stores code signing certificates and provisioning profiles in a private Git repository.

#### 1. Create Certificates Repository

```bash
# Create a new private repo on GitHub: victorquinn/certificates
# This will store encrypted certificates and profiles
```

#### 2. Generate SSH Deploy Key

```bash
# Generate SSH key for CI
ssh-keygen -t ed25519 -C "dequeue-ci@github" -f ~/.ssh/dequeue_ci_key -N ""

# Add public key to certificates repo as deploy key (read/write)
cat ~/.ssh/dequeue_ci_key.pub
# → GitHub → certificates repo → Settings → Deploy Keys → Add

# Add private key to GitHub secrets
cat ~/.ssh/dequeue_ci_key
# → GitHub → dequeue-ios → Settings → Secrets → MATCH_DEPLOY_KEY
```

#### 3. Initialize Match

```bash
cd Dequeue
bundle install

# Initialize Match (first time only)
MATCH_PASSWORD="your-secure-password" \
MATCH_GIT_URL="git@github.com:victorquinn/certificates.git" \
bundle exec fastlane match appstore --readonly false

# This will:
# - Create/download certificates
# - Create/download provisioning profiles
# - Store them encrypted in certificates repo
```

### App Store Connect API Key Setup

#### 1. Create API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to Users & Access → Keys
3. Click the "+" button to create a new key
4. Name: "Dequeue CI"
5. Access: "Developer" or "App Manager"
6. Download the `.p8` file (you can only do this once!)

#### 2. Extract Key Information

```bash
# Key ID and Issuer ID are shown in App Store Connect
# Copy them to GitHub secrets: ASC_KEY_ID, ASC_ISSUER_ID

# Encode the .p8 file to base64
base64 < AuthKey_ABCD1234.p8 | pbcopy
# Paste into GitHub secret: ASC_KEY_CONTENT
```

## Local Testing

You can test the Fastlane setup locally:

```bash
cd Dequeue

# Install dependencies
bundle install

# Sync certificates (development)
bundle exec fastlane sync_dev_certs

# Build and upload to TestFlight (requires secrets)
MATCH_PASSWORD="..." \
ASC_KEY_ID="..." \
ASC_ISSUER_ID="..." \
ASC_KEY_CONTENT="..." \
bundle exec fastlane beta
```

## Build Number Management

Fastlane automatically increments the build number based on the latest TestFlight build:

```ruby
increment_build_number(
  build_number: latest_testflight_build_number + 1,
  xcodeproj: "Dequeue.xcodeproj"
)
```

This ensures:
- No manual version bumping needed
- No build number conflicts
- Sequential build numbers

## Troubleshooting

### "No matching provisioning profiles found"

**Solution:** Run Match to generate profiles:
```bash
cd Dequeue
bundle exec fastlane match appstore --readonly false
```

### "Certificate has expired"

**Solution:** Renew certificates with Match:
```bash
cd Dequeue
bundle exec fastlane match appstore --force_for_new_devices
```

### "Build failed: Code signing error"

**Checklist:**
1. Verify `MATCH_DEPLOY_KEY` has read/write access to certificates repo
2. Verify `MATCH_PASSWORD` is correct
3. Check Match repository has valid certificates (not expired)
4. Run `fastlane match appstore` locally to validate setup

### "App Store Connect API authentication failed"

**Checklist:**
1. Verify `ASC_KEY_ID` and `ASC_ISSUER_ID` are correct
2. Verify `ASC_KEY_CONTENT` is base64-encoded correctly
3. Check API key has "Developer" or "App Manager" access
4. Verify API key hasn't been revoked in App Store Connect

## Comparison to Old Approach

### Before (raw xcodebuild)
- ❌ Manual code signing configuration
- ❌ Manual build number increments
- ❌ Complex xcodebuild commands
- ❌ Hard to debug failures
- ❌ No local testing without secrets in shell

### After (Fastlane)
- ✅ Automated code signing with Match
- ✅ Automatic build number increments
- ✅ Simple `fastlane beta` command
- ✅ Clear error messages
- ✅ Easy local testing
- ✅ Proven approach (used by Minsa)

## Resources

- [Fastlane Documentation](https://docs.fastlane.tools/)
- [Match Guide](https://docs.fastlane.tools/actions/match/)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [Minsa Fastlane Setup](../clawd-minsa/repo/apps/ios/Minsa/fastlane/) (reference implementation)
