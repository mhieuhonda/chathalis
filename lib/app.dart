import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/chat_repository.dart';
import 'engine/app_store.dart';
import 'engine/usage_tracker.dart';
import 'ui/home/home_screen.dart';

class ChatHalisApp extends StatelessWidget {
  const ChatHalisApp({super.key, this.usage, this.repository});

  /// The hourly-budget tracker and the persistence layer. Injectable so
  /// tests can own their lifetimes; production uses the defaults.
  final UsageTracker? usage;
  final ChatRepository? repository;

  UsageTracker get _usage => usage ?? UsageTracker.instance;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppStore(repository: repository)..load(),
        ),
        ChangeNotifierProvider.value(value: _usage),
      ],
      // A context *below* the providers so the MaterialApp rebuilds when
      // the theme or language flips.
      child: Builder(
        builder: (context) {
          final store = context.watch<AppStore>();

          return MaterialApp(
            title: 'ChatHalis',
            debugShowCheckedModeBanner: false,
            theme: HalisTheme.light(),
            darkTheme: HalisTheme.dark(),
            themeMode:
                store.theme == ThemeSetting.dark ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
