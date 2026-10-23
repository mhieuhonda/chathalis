import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../engine/app_store.dart';
import '../../gateway/models.dart';

/// The small chips above an answer that show what Halis did to earn it:
/// searched the web, read a page, checked the time. Live chips carry a
/// spinner; finished ones show how long the tool took.
class ToolTraceView extends StatelessWidget {
  const ToolTraceView({super.key, required this.uses});

  final List<ToolUse> uses;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final u in uses) _ToolChip(use: u, palette: c)],
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.use, required this.palette});

  final ToolUse use;
  final HalisStyle palette;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().strings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconFor(use.tool),
            size: 13,
            color: use.running ? palette.accent : palette.inkSoft,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              s.toolDoing(use.tool, use.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: palette.inkSoft,
              ),
            ),
          ),
          if (use.running) ...[
            const SizedBox(width: 6),
            const SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.4),
            ),
          ] else if (use.ms != null) ...[
            const SizedBox(width: 6),
            Text(
              _briefMs(use.ms!),
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: palette.inkFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconFor(String tool) => switch (tool) {
        'websearch' => Icons.travel_explore_rounded,
        'webfetch' => Icons.article_outlined,
        'datetime' => Icons.schedule_rounded,
        _ => Icons.construction_rounded,
      };

  /// `0s` / `2s` / `1m 04s` — compact enough to sit inside a chip.
  String _briefMs(int ms) {
    if (ms < 1000) return '0s';
    final seconds = ms ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${(seconds % 60).toString().padLeft(2, '0')}s';
  }
}
