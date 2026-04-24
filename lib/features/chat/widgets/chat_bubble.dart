import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final String? imageData;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.imageData,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedAlign(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        constraints: const BoxConstraints(maxWidth: 740),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : colors.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageData != null) ...[
              _InlineImage(dataUri: imageData!),
              if (content.trim().isNotEmpty) const SizedBox(height: 10),
            ],
            if (isUser)
              SelectableText(
                content,
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                ),
              )
            else
              MarkdownBody(
                data: content,
                selectable: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _InlineImage extends StatelessWidget {
  final String dataUri;

  const _InlineImage({required this.dataUri});

  @override
  Widget build(BuildContext context) {
    final idx = dataUri.indexOf(',');
    if (idx < 0) return const SizedBox.shrink();
    final bytes = base64Decode(dataUri.substring(idx + 1));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.memory(bytes, fit: BoxFit.cover, height: 220),
    );
  }
}
