import '../../../core/storage/local_storage_service.dart';
import '../models/artifact.dart';

class ArtifactLocalStore {
  static const _key = 'sigmaai_artifacts';
  final LocalStorageService _storage;

  ArtifactLocalStore(this._storage);

  Future<List<Artifact>> loadArtifacts() async {
    try {
      final list = await _storage.readJsonList(_key);
      return list.map(Artifact.fromJson).toList();
    } catch (_) {
      await _storage.writeJsonList(_key, []);
      return [];
    }
  }

  Future<void> saveArtifacts(List<Artifact> artifacts) {
    return _storage.writeJsonList(_key, artifacts.map((e) => e.toJson()).toList());
  }
}
