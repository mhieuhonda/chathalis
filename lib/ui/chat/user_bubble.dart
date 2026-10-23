import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Right-aligned ink bubble carrying the user's message.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: const BoxDecoration(
            color: HalisPalette.ink,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: SelectionArea(
            child: Text(
              text,
              style: const TextStyle(
                color: HalisPalette.paper,
                fontSize: 15.5,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
