import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chathalis/core/theme.dart';

/// The whole UI reads colors through `context.halis`, so both themes must
/// always carry the extension.
void main() {
  testWidgets('the light theme carries HalisStyle', (tester) async {
    late HalisStyle seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: HalisTheme.light(),
        home: Builder(
          builder: (context) {
            seen = context.halis;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(seen.paper, HalisStyle.light.paper);
    expect(seen.ink, HalisStyle.light.ink);
  });

  testWidgets('the dark theme carries HalisStyle', (tester) async {
    late HalisStyle seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: HalisTheme.light(),
        darkTheme: HalisTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            seen = context.halis;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(seen.paper, HalisStyle.dark.paper);
    expect(seen.ink, HalisStyle.dark.ink);
  });

  testWidgets('styles lerp without gaps between themes', (tester) async {
    // Exercises the ThemeExtension.lerp contract used by theme transitions.
    final lerped = HalisStyle.light.lerp(HalisStyle.dark, 0.5);
    expect(lerped.paper, Color.lerp(HalisStyle.light.paper, HalisStyle.dark.paper, 0.5));
    expect(lerped.accent, Color.lerp(HalisStyle.light.accent, HalisStyle.dark.accent, 0.5));
    expect(lerped.warnSoft, Color.lerp(HalisStyle.light.warnSoft, HalisStyle.dark.warnSoft, 0.5));
  });
}
