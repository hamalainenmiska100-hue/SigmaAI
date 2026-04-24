import 'package:flutter/material.dart';

import '../../core/storage/local_storage_service.dart';
import '../../core/widgets/empty_state.dart';
import 'artifact_viewer_screen.dart';
import 'models/artifact.dart';
import 'services/artifact_local_store.dart';
import 'widgets/artifact_list_card.dart';

class ArtifactsScreen extends StatefulWidget {
  const ArtifactsScreen({super.key});

  @override
  State<ArtifactsScreen> createState() => _ArtifactsScreenState();
}

class _ArtifactsScreenState extends State<ArtifactsScreen> {
  final _store = ArtifactLocalStore(LocalStorageService());
  List<Artifact> _artifacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _store.loadArtifacts();
    if (!mounted) return;
    setState(() => _artifacts = items.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Artifacts')),
      body: _artifacts.isEmpty
          ? const EmptyState(text: 'No artifacts yet.')
          : ListView.builder(
              itemCount: _artifacts.length,
              itemBuilder: (context, index) {
                final artifact = _artifacts[index];
                return ArtifactListCard(
                  artifact: artifact,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ArtifactViewerScreen(artifact: artifact)),
                    );
                  },
                );
              },
            ),
    );
  }
}
