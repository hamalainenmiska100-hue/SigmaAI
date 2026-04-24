import 'package:flutter/material.dart';

class MessageInput extends StatefulWidget {
  final bool enabled;
  final Future<void> Function(String text) onSend;
  final Future<void> Function() onPickImage;
  final bool hasPendingImage;
  final VoidCallback onRemoveImage;

  const MessageInput({
    super.key,
    required this.enabled,
    required this.onSend,
    required this.onPickImage,
    required this.hasPendingImage,
    required this.onRemoveImage,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final controller = TextEditingController();

  Future<void> submit() async {
    final text = controller.text.trim();

    if ((text.isEmpty && !widget.hasPendingImage) || !widget.enabled) {
      return;
    }

    controller.clear();
    await widget.onSend(text);
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
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: colors.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.hasPendingImage)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.image_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Photo attached')),
                    IconButton(
                      onPressed: widget.onRemoveImage,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: widget.enabled ? widget.onPickImage : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: widget.enabled ? 'Message Sigma...' : 'Generating response...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: widget.enabled ? submit : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
