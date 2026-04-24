import '../../../core/config/app_config.dart';
import '../../../core/storage/local_storage_service.dart';

class SettingsService {
  static const _key = 'sigmaai_custom_instructions';
  final LocalStorageService _storage;

  SettingsService(this._storage);

  Future<String> loadCustomInstructions() async {
    return _storage.readString(_key);
  }

  Future<void> saveCustomInstructions(String value) async {
    final text = value.length > AppConfig.maxCustomInstructionsLength
        ? value.substring(0, AppConfig.maxCustomInstructionsLength)
        : value;
    await _storage.writeString(_key, text);
  }
}
