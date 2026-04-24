import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'models/artifact.dart';
import 'services/artifact_file_service.dart';
import 'widgets/artifact_actions.dart';

class ArtifactViewerScreen extends StatelessWidget {
  final Artifact artifact;

  const ArtifactViewerScreen({super.key, required this.artifact});

  @override
  Widget build(BuildContext context) {
    final service = ArtifactFileService();

    Future<void> copy() async {
      await service.copy(artifact);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
    }

    Future<void> share() async {
      try {
        await service.share(artifact);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share artifact')));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(artifact.filename),
        actions: [ArtifactActions(onCopy: copy, onShare: share)],
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        child: artifact.isMarkdown
            ? Markdown(
                data: artifact.content,
                selectable: true,
              )
            : SelectableText(
                artifact.content,
                style: const TextStyle(fontFamily: 'monospace', height: 1.4),
              ),
      ),
    );
  }
}
