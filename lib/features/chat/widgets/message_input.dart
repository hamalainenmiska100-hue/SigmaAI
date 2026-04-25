import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/image_attachment_service.dart';

class MessageInput extends StatefulWidget {
  final bool canSend;
  final bool isGenerating;
  final Future<void> Function(String text, {List<String> imageData}) onSend;
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
  List<String> _attachedImages = [];

  Future<void> submit() async {
    final text = controller.text.trim();
    final imageData = _attachedImages.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    if ((text.isEmpty && imageData.isEmpty) || !widget.canSend) {
      return;
    }

    controller.clear();
    setState(() => _attachedImages = []);
    await widget.onSend(text, imageData: imageData);
  }

  Future<void> _pickImageFromDevice() async {
    if (_attachedImages.length >= 3) return;
    final picked = await _imageAttachmentService.pickCompressedImageDataUri();
    if (!mounted || picked == null) return;
    setState(() {
      _attachedImages = [..._attachedImages, picked].take(3).toList();
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
                    _attachedImages.isEmpty ? Icons.image_outlined : Icons.image,
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
                          ? (_attachedImages.isEmpty ? 'Message Sigma...' : 'Message about attached images...')
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
            if (_attachedImages.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachedImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final image = _attachedImages[index];
                    final bytes = imageAttachmentBytes(image);
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: bytes.isEmpty
                              ? Container(
                                  width: 70,
                                  height: 70,
                                  color: colors.surfaceContainerHighest,
                                  child: const Icon(Icons.broken_image_outlined),
                                )
                              : Image.memory(
                                  bytes,
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                final next = [..._attachedImages];
                                next.removeAt(index);
                                _attachedImages = next;
                              });
                            },
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Uint8List imageAttachmentBytes(String dataUri) {
  final comma = dataUri.indexOf(',');
  if (comma < 0 || comma + 1 >= dataUri.length) return Uint8List(0);
  try {
    return base64Decode(dataUri.substring(comma + 1));
  } catch (_) {
    return Uint8List(0);
  }
}
