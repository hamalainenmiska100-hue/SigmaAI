import 'package:flutter/material.dart';

import '../../artifacts/models/artifact.dart';

class ChatArtifactCard extends StatelessWidget {
  final Artifact artifact;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const ChatArtifactCard({
    super.key,
    required this.artifact,
    required this.onOpen,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final isPreparing = artifact.status == 'preparing';
    final isFailed = artifact.status == 'failed';

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: ListTile(
        leading: isPreparing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.description_outlined),
        title: Text(artifact.filename.isEmpty ? 'Artifact' : artifact.filename),
        subtitle: Text(isPreparing
            ? 'Preparing artifact...'
            : isFailed
                ? 'Failed to create artifact'
                : 'Artifact ready'),
        trailing: Wrap(
          spacing: 8,
          children: [
            TextButton(onPressed: isPreparing ? null : onOpen, child: const Text('Open')),
            TextButton(onPressed: isPreparing ? null : onCopy, child: const Text('Copy')),
            TextButton(onPressed: isPreparing ? null : onShare, child: const Text('Share')),
          ],
        ),
      ),
    );
  }
}
