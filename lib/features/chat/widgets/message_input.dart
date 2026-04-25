import 'package:flutter/material.dart';

import '../services/image_attachment_service.dart';

class MessageInput extends StatefulWidget {
  final bool canSend;
  final bool isGenerating;
  final Future<void> Function(String text, {String? imageData}) onSend;
  final VoidCallback onStop;

  const MessageInput({
    super.key,
    required this.canSend,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final controller = TextEditingController();
  final _imageAttachmentService = ImageAttachmentService();
  String? _attachedImageData;

  Future<void> submit() async {
    final text = controller.text.trim();
    final imageData = _attachedImageData?.trim();

    if ((text.isEmpty && (imageData == null || imageData.isEmpty)) || !widget.canSend) {
      return;
    }

    controller.clear();
    setState(() => _attachedImageData = null);
    await widget.onSend(text, imageData: imageData);
  }

  Future<void> _pickImageFromDevice() async {
    final picked = await _imageAttachmentService.pickCompressedImageDataUri();
    if (!mounted || picked == null) return;
    setState(() {
      _attachedImageData = picked;
    });
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
              child: widget.isGenerating
                  ? Padding(
                      key: const ValueKey('generating-indicator'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          color: colors.primary,
                          backgroundColor: colors.surfaceContainerHighest,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('idle-indicator')),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: widget.canSend ? _pickImageFromDevice : null,
                  tooltip: 'Attach image',
                  icon: Icon(
                    _attachedImageData == null ? Icons.image_outlined : Icons.image,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: widget.canSend,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: widget.canSend
                          ? (_attachedImageData == null ? 'Message Sigma...' : 'Message about attached image...')
                          : 'Sigma is responding...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: widget.isGenerating
                      ? IconButton.filled(
                          key: const ValueKey('stop-button'),
                          onPressed: widget.onStop,
                          icon: const Icon(Icons.stop_rounded),
                        )
                      : IconButton.filled(
                          key: const ValueKey('send-button'),
                          onPressed: widget.canSend ? submit : null,
                          icon: const Icon(Icons.arrow_upward),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
