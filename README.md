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

Current URL:

`https://chat.vymedia.xyz/chat`

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
