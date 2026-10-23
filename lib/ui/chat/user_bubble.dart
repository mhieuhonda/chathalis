import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Right-aligned ink bubble carrying the user's message.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: c.ink,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: SelectionArea(
            child: Text(
              text,
              style: TextStyle(
                color: c.paper,
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
