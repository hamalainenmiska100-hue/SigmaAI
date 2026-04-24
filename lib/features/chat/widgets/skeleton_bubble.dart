import 'package:flutter/material.dart';

import 'skeleton_line.dart';

class SkeletonBubble extends StatelessWidget {
  const SkeletonBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 290,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withOpacity(0.65),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLine(width: 230),
            SizedBox(height: 10),
            SkeletonLine(width: 180),
            SizedBox(height: 10),
            SkeletonLine(width: 250),
            SizedBox(height: 10),
            SkeletonLine(width: 130),
          ],
        ),
      ),
    );
  }
}
