import '../../../core/storage/local_storage_service.dart';

enum AssistantLanguage {
  english,
  swedish,
  finnish,
}

enum AssistantTone {
  normal,
  unhinged,
  spicy,
}

class UserSettings {
  final AssistantLanguage language;
  final AssistantTone tone;

  const UserSettings({
    required this.language,
    required this.tone,
  });
}

class SettingsService {
  static const _languageKey = 'sigmaai_language';
  static const _toneKey = 'sigmaai_tone';

  final LocalStorageService _storage;

  SettingsService(this._storage);

  Future<UserSettings> loadSettings() async {
    final languageRaw = await _storage.readString(_languageKey);
    final toneRaw = await _storage.readString(_toneKey);

    return UserSettings(
      language: _parseLanguage(languageRaw),
      tone: _parseTone(toneRaw),
    );
  }

  Future<void> saveLanguage(AssistantLanguage language) async {
    await _storage.writeString(_languageKey, language.name);
  }

  Future<void> saveTone(AssistantTone tone) async {
    await _storage.writeString(_toneKey, tone.name);
  }

  AssistantLanguage _parseLanguage(String value) {
    for (final item in AssistantLanguage.values) {
      if (item.name == value) return item;
    }
    return AssistantLanguage.english;
  }

  AssistantTone _parseTone(String value) {
    for (final item in AssistantTone.values) {
      if (item.name == value) return item;
    }
    return AssistantTone.normal;
  }
}
