import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

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

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            padding: isUser ? const EdgeInsets.all(14) : const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: isUser
                ? BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.16)),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageData != null && imageData!.isNotEmpty) ...[
                  _ImagePreview(
                    imageUrl: imageData!,
                  ),
                  if (content.trim().isNotEmpty) const SizedBox(height: 8),
                ],
                if (content.trim().isNotEmpty)
                  isUser
                      ? SelectableText(
                          content,
                          style: TextStyle(
                            color: colors.onPrimaryContainer,
                          ),
                        )
                      : MarkdownBody(
                          data: content,
                          selectable: true,
                          builders: {
                            'code': InlineCodeBuilder(),
                          },
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final String imageUrl;

  const _ImagePreview({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (_) => Dialog.fullscreen(
            child: Stack(
              children: [
                InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 280,
            maxWidth: 360,
          ),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: colors.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: const Text('Unable to load image preview'),
            ),
          ),
        ),
      ),
    );
  }
}

class InlineCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final isInline = !element.textContent.contains('\n');
    if (!isInline) {
      return null;
    }

    final code = element.textContent.trim();
    if (code.isEmpty) {
      return null;
    }

    return _InlineCodeChip(text: code);
  }
}

class _InlineCodeChip extends StatefulWidget {
  final String text;

  const _InlineCodeChip({required this.text});

  @override
  State<_InlineCodeChip> createState() => _InlineCodeChipState();
}

class _InlineCodeChipState extends State<_InlineCodeChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                color: colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: _copy,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                _copied ? Icons.check : Icons.copy_rounded,
                size: 14,
                color: _copied ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
