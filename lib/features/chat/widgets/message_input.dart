import 'package:flutter/material.dart';

class MessageInput extends StatefulWidget {
  final bool enabled;
  final ValueChanged<String> onSend;

  const MessageInput({
    super.key,
    required this.enabled,
    required this.onSend,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final controller = TextEditingController();

  void submit() {
    final text = controller.text.trim();

    if (text.isEmpty || !widget.enabled) {
      return;
    }

    controller.clear();
    widget.onSend(text);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: colors.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: widget.enabled ? 'Message SigmaAI...' : 'Generating response...',
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: widget.enabled
                  ? IconButton.filled(
                      key: const ValueKey('send'),
                      onPressed: submit,
                      icon: const Icon(Icons.arrow_upward),
                    )
                  : IconButton(
                      key: const ValueKey('loading'),
                      onPressed: null,
                      icon: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
