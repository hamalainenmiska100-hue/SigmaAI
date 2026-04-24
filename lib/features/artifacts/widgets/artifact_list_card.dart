import 'package:flutter/material.dart';

import '../../../core/utils/date_formatting.dart';
import '../models/artifact.dart';

class ArtifactListCard extends StatelessWidget {
  final Artifact artifact;
  final VoidCallback onTap;

  const ArtifactListCard({
    super.key,
    required this.artifact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        title: Text(artifact.filename),
        subtitle: Text('${artifact.fileType} • ${DateFormatting.short(artifact.createdAt)}'),
        trailing: const Text('Open'),
      ),
    );
  }
}
