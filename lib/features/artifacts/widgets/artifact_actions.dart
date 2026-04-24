import 'package:flutter/material.dart';

class ArtifactActions extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const ArtifactActions({
    super.key,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: onCopy, child: const Text('Copy')),
        TextButton(onPressed: onShare, child: const Text('Share')),
      ],
    );
  }
}
