import 'package:flutter/material.dart';

import 'skeleton_bubble.dart';

class ChatLoadingArea extends StatelessWidget {
  final bool isLoading;

  const ChatLoadingArea({
    super.key,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: 1,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: isLoading
          ? const Column(
              key: ValueKey('loading'),
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBubble(),
                LinearProgressIndicator(minHeight: 2),
              ],
            )
          : const SizedBox(
              key: ValueKey('empty'),
              height: 2,
            ),
    );
  }
}
