# SigmaAI

SigmaAI is a simple Flutter chat app with three tabs: Chat, Artifacts, and Settings.
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

- Chat history key: `sigmaai_chat_messages`
- Artifacts key: `sigmaai_artifacts`
- Custom instructions key: `sigmaai_custom_instructions`

## Supported text artifacts

- `.md`
- `.txt`
- `.json`
- `.html`
- `.css`
- `.js`
- `.ts`
- `.py`
- `.csv`

## Not supported

- Image generation
- Video generation
- Audio generation
- Binary and media artifact files

## iOS build

You can generate iOS platform files and build a release app bundle with:

```bash
flutter pub get
flutter create --platforms=ios .
flutter build ios --release --no-codesign
```

This repository also includes a GitHub Actions workflow (`.github/workflows/build-ios.yml`)
that builds iOS on `macos-latest` and uploads `build/ios` as an artifact.
