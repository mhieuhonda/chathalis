import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/app_store.dart';
import '../../engine/usage_tracker.dart';
import '../widgets/halis_mark.dart';

/// Settings: about the app, usage, preferences (appearance, language)
/// and a full data wipe.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const SettingsScreen());

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = store.strings;
    final (convs, msgs) = store.counts;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.settings,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          _GroupLabel(s.aboutSection),
          _AboutCard(s: s),
          const SizedBox(height: 22),
          _GroupLabel(s.usageSection),
          const _UsageCard(),
          const SizedBox(height: 22),
          _GroupLabel(s.preferencesSection),
          _PreferencesCard(store: store, s: s),
          const SizedBox(height: 22),
          _GroupLabel(s.dataSection),
          _DataCard(store: store, s: s, convs: convs, msgs: msgs),
          const SizedBox(height: 26),
          Center(
            child: Text(
              s.developedBy,
              style: TextStyle(
                fontSize: 12,
                color: context.halis.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hourly budget, shown as a percentage — the way Claude's usage
/// screen does. Never request counts, and a caught 429 pins it at 100%
/// until the cooldown lapses.
class _UsageCard extends StatelessWidget {
  const _UsageCard();

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<UsageTracker>();
    final s = context.watch<AppStore>().strings;
    final c = context.halis;
    final locked = usage.locked;
    final percent = usage.percent;

    return _Card(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: locked ? c.dangerSoft : c.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    locked
                        ? Icons.hourglass_top_rounded
                        : Icons.bolt_rounded,
                    size: 17,
                    color: locked ? c.danger : c.accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.usageTitle,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locked ? s.usageLimitReached : s.usageUsed(percent),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: locked ? c.danger : c.inkSoft,
                          fontWeight: locked ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Text(
                    '$percent%',
                    key: ValueKey<int>(percent),
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: locked ? c.danger : c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _UsageBar(fraction: usage.fraction, locked: locked),
            if (locked) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 13, color: c.danger),
                  const SizedBox(width: 6),
                  Text(
                    s.usageChatAgainIn(usage.remainingLock),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: c.danger,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      _Hairline(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
        child: Row(
          children: [
            Icon(Icons.autorenew_rounded, size: 13, color: c.inkFaint),
            const SizedBox(width: 6),
            Text(
              s.usageNote,
              style: TextStyle(
                fontSize: 11.5,
                color: c.inkFaint,
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Slim capsule meter; the fill colors up as the budget drains and turns
/// red the moment the hour is up.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.fraction, required this.locked});

  final double fraction;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    final fill = locked
        ? c.danger
        : (fraction >= 0.8 ? c.warn : c.ink);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: c.paper,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: fraction.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, f, _) => FractionallySizedBox(
            widthFactor: f,
            child: Container(height: 6, color: fill),
          ),
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return _Card(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: c.ink,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: HalisMark(size: 26, color: c.paper),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        s.appName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '1.0.0',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.modelLine,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _Hairline(),
      _InfoRow(label: s.version, value: '1.0.0'),
      _Hairline(),
      _InfoRow(label: s.engineLabel, value: s.engineValue),
    ]);
  }
}

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({required this.store, required this.s});

  final AppStore store;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return _Card(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            Icon(Icons.dark_mode_outlined, size: 18, color: c.inkSoft),
            const SizedBox(width: 10),
            Text(s.appearanceTitle,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: _Segmented<String>(
          value: store.theme.name,
          items: [
            (s.appearanceLight, 'light'),
            (s.appearanceDark, 'dark'),
          ],
          onChanged: (v) => store.setTheme(
              v == 'dark' ? ThemeSetting.dark : ThemeSetting.light),
        ),
      ),
      _Hairline(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            Icon(Icons.language_rounded, size: 18, color: c.inkSoft),
            const SizedBox(width: 10),
            Text(s.languageTitle,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: _Segmented<AppLocale>(
          value: store.locale.name,
          items: [
            (s.langEnglish, 'english'),
            (s.langVietnamese, 'vietnamese'),
          ],
          onChanged: (v) => store
              .setLocale(v == 'vietnamese' ? AppLocale.vietnamese : AppLocale.english),
        ),
      ),
    ]);
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({
    required this.store,
    required this.s,
    required this.convs,
    required this.msgs,
  });

  final AppStore store;
  final Strings s;
  final int convs;
  final int msgs;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return _Card(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined, size: 18, color: c.inkSoft),
                const SizedBox(width: 10),
                Text(
                  s.dataCounts(convs, msgs),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.dataStoredLocally,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: c.inkSoft,
              ),
            ),
          ],
        ),
      ),
      _Hairline(),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: TextButton.icon(
          onPressed: () => _confirmClear(context, store),
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: Text(
            s.clearAllData,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          style: TextButton.styleFrom(
            foregroundColor: c.danger,
          ),
        ),
      ),
    ]);
  }

  Future<void> _confirmClear(BuildContext context, AppStore store) async {
    final s = context.read<AppStore>().strings;
    final c = context.halis;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          s.clearAllData,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: Text(
          s.clearAllConfirm,
          style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.clearAll();
      if (context.mounted) {
        final s = context.read<AppStore>().strings;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.cleared)));
      }
    }
  }
}

/// Claude-style segmented control: a sunken track with pill buttons, the
/// active segment lifting onto the paper with a soft shadow.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  /// The active segment's key.
  final String value;

  /// (label, key) pairs, two segments each.
  final List<(String, String)> items;

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          for (final (label, key) in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: key == value ? c.paper : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: key == value
                        ? [
                            BoxShadow(
                              color: c.shadow,
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: key == value ? c.ink : c.inkFaint,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: c.inkFaint,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: children),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Divider(height: 1, color: c.hairline),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.halis;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13.5, color: c.inkSoft)),
          Text(value,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
