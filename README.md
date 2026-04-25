# Sigma

Sigma is a Flutter chat app with realtime streaming responses, photo prompts, local chat history, and a customizable UI.
It sends chat requests to a single proxy URL and stores chat data locally on-device.

## Run

```bash
flutter pub get
flutter run
```

## Proxy configuration

Proxy URL is configured in:

`lib/core/config/app_config.dart`

Base URL:

`https://chat.vymedia.xyz`

The app targets `/chat` automatically when the base URL has no explicit path.

The Flutter app does not store or include any provider API keys.

## Local storage

This MVP stores data locally with `shared_preferences`:

- Chat threads key: `sigma_chat_threads`
- Per-thread messages key: `sigma_chat_messages_<threadId>`
- Custom instructions key: `sigmaai_custom_instructions`


## Cloudflare Pages deployment (GitHub Actions)

This repo deploys Flutter web to Cloudflare Pages via:

`/.github/workflows/deploy-pages.yml`

Configure these in your GitHub repository before running the workflow:

1. **Secret** `CF_TOKEN`
   - Cloudflare API token with **Account → Cloudflare Pages: Edit** permission.
2. **Secret** `CF_ACCOUNT_ID`
   - Your Cloudflare account ID.
3. **Variable** `CF_PAGES_PROJECT`
   - Exact Cloudflare Pages project name (case-sensitive).

GitHub path: **Settings → Secrets and variables → Actions**

Then trigger deployment by:
- pushing to `main`, or
- running **Actions → Build and Deploy Flutter Web to Cloudflare Pages → Run workflow**.

If the workflow fails immediately with a "Missing ..." message, one of the required values above is not set correctly.

## Notes

- Chat supports text streaming + image inputs via a Cloudflare Worker proxy.
- Image attachments are compressed locally before storage and upload.

## iOS build

You can generate iOS platform files and build a release app bundle with:

```bash
flutter pub get
flutter create --platforms=ios .
flutter build ios --release --no-codesign
```

This repository also includes a GitHub Actions workflow (`.github/workflows/build-ios.yml`)
that builds iOS on `macos-latest` and uploads `build/ios` as an artifact.
