import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : colors.surfaceContainerHighest.withOpacity(0.65),
          borderRadius: BorderRadius.circular(22),
        ),
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
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                  tableCellsPadding: const EdgeInsets.all(10),
                  codeblockDecoration: BoxDecoration(
                    color: colors.surface.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: colors.surfaceContainerHigh.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(
                        color: colors.primary,
                        width: 4,
                      ),
                    ),
                  ),
                ),
                builders: {
                  'table': _TableBuilder(),
                },
              ),
      ),
    );
  }
}

class _TableBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(element, preferredStyle) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: super.visitElementAfter(element, preferredStyle),
    );
  }
}
