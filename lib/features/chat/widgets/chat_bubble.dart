import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
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
            child: isUser
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
