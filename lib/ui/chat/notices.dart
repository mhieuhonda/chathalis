import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../engine/app_store.dart';

/// Amber inline notice shown when a reply is cut off by the 32k output cap.
class TruncationNotice extends StatelessWidget {
  const TruncationNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.warnSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 17,
            color: c.warn,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              context.watch<AppStore>().strings.truncatedNotice,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: c.warn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muted one-liner for replies the user stopped mid-generation.
class StoppedNotice extends StatelessWidget {
  const StoppedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stop_circle_outlined, size: 13, color: c.inkFaint),
          const SizedBox(width: 6),
          Text(
            context.watch<AppStore>().strings.stopped,
            style: TextStyle(
              fontSize: 12.5,
              color: c.inkFaint,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error card with an inline retry action.
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(
        color: c.dangerSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 17, color: c.danger),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                    color: c.danger,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: c.danger,
                minimumSize: const Size(44, 34),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(context.watch<AppStore>().strings.retry),
            ),
          ),
        ],
      ),
    );
  }
}
