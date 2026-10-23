import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/app_store.dart';
import '../widgets/halis_mark.dart';

/// Minimal settings: about the app, and full data wipe.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const SettingsScreen());

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final (convs, msgs) = store.counts;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          HalisStrings.settings,
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          const _GroupLabel(HalisStrings.aboutSection),
          _Card(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: HalisPalette.ink,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: HalisMark(size: 26, color: HalisPalette.paper),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              HalisStrings.appName,
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
                                color: HalisPalette.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '1.0.0',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: HalisPalette.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          HalisStrings.modelLine,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: HalisPalette.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _Hairline(),
            const _InfoRow(label: HalisStrings.version, value: '1.0.0'),
            const _Hairline(),
            const _InfoRow(label: 'Engine', value: 'Flutter · Dart 3.13'),
          ]),
          const SizedBox(height: 22),
          const _GroupLabel(HalisStrings.dataSection),
          _Card(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storage_outlined,
                          size: 18, color: HalisPalette.inkSoft),
                      const SizedBox(width: 10),
                      Text(
                        '$convs cuộc trò chuyện · $msgs tin nhắn',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    HalisStrings.dataStoredLocally,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: HalisPalette.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const _Hairline(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: TextButton.icon(
                onPressed: () => _confirmClear(context, store),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text(
                  HalisStrings.clearAllData,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: HalisPalette.danger,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 26),
          const Center(
            child: Text(
              'Halis · được phát triển bởi Hieu Louis',
              style: TextStyle(
                fontSize: 12,
                color: HalisPalette.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          HalisStrings.clearAllData,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          HalisStrings.clearAllConfirm,
          style: TextStyle(
              fontSize: 14, height: 1.5, color: HalisPalette.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(HalisStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: HalisPalette.danger),
            child: const Text(HalisStrings.delete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(HalisStrings.cleared)));
      }
    }
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: HalisPalette.inkFaint,
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HalisPalette.surface,
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
    return const Padding(
      padding: EdgeInsets.only(left: 16),
      child: Divider(height: 1, color: HalisPalette.hairline),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13.5, color: HalisPalette.inkSoft)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
