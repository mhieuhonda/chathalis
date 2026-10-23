import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../engine/app_store.dart';

/// Collapsible chain-of-thought panel, DeepSeek-style: live while the model
/// thinks, collapsed to a one-line summary once the answer starts.
class ThinkingPanel extends StatefulWidget {
  const ThinkingPanel({
    super.key,
    required this.reasoning,
    required this.streaming,
    this.reasoningMs,
  });

  final String reasoning;
  final bool streaming;
  final int? reasoningMs;

  @override
  State<ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<ThinkingPanel> {
  bool _expanded = false;
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _expanded = widget.streaming && widget.reasoning.isNotEmpty;
    _scroll.addListener(() {
      if (_scroll.hasClients) {
        final atBottom = _scroll.offset >= _scroll.position.maxScrollExtent - 24;
        _autoScroll = atBottom;
      }
    });
  }

  @override
  void didUpdateWidget(ThinkingPanel old) {
    super.didUpdateWidget(old);
    // While thinking, the panel is expanded and follows the live text.
    if (widget.streaming && !_expanded) {
      _expanded = true;
    }
    if (widget.streaming && old.reasoning != widget.reasoning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_autoScroll || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppStore>().strings;
    final c = context.halis;
    final live = widget.streaming;
    final heading = live
        ? s.thinkingNow
        : '${s.thoughtFor}${widget.reasoningMs == null ? '' : ' · ${s.humanDuration(widget.reasoningMs!)}'}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header — always visible.
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: live ? null : () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.psychology_rounded,
                        size: 16,
                        color: live ? c.accent : c.inkSoft,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              heading,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: c.inkSoft,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(width: 2),
                            if (live) const _LiveEllipsis(),
                          ],
                        ),
                      ),
                      if (!live)
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: c.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Body.
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: _buildBody(c),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(HalisStyle c) {
    final text = widget.reasoning.trim();
    if (text.isEmpty) return const SizedBox(width: double.infinity);
    return Container(
      constraints: const BoxConstraints(maxHeight: 230),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _scroll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: c.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots breathing in sequence while the model thinks.
class _LiveEllipsis extends StatefulWidget {
  const _LiveEllipsis();

  @override
  State<_LiveEllipsis> createState() => _LiveEllipsisState();
}

class _LiveEllipsisState extends State<_LiveEllipsis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return FadeTransition(
          opacity: _c.drive(
            CurveTween(
              curve: Interval(0.12 * i, 0.12 * i + 0.45,
                  curve: const _BreatheCurve()),
            ),
          ),
          child: _Dot(c.inkSoft),
        );
      }),
    );
  }
}

class _BreatheCurve extends Curve {
  const _BreatheCurve();

  @override
  double transformInternal(double t) =>
      0.25 + 0.75 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3.5,
      height: 3.5,
      margin: const EdgeInsets.symmetric(horizontal: 1.2),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Typing indicator shown before the first byte of a turn arrives.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = (_c.value * 3 - i).clamp(0.0, 1.0);
            final opacity = 0.25 + 0.75 * _ease(t);
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: c.inkFaint.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }

  double _ease(double t) => 0.5 - 0.5 * math.cos(t * math.pi);
}
