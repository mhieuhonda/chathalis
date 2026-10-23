import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'engine/app_store.dart';
import 'engine/usage_tracker.dart';
import 'ui/home/home_screen.dart';

class ChatHalisApp extends StatelessWidget {
  const ChatHalisApp({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UsageTracker.instance),
      ],
      child: MaterialApp(
        title: 'ChatHalis',
        debugShowCheckedModeBanner: false,
        theme: HalisTheme.light(),
        darkTheme: HalisTheme.dark(),
        themeMode: store.theme == ThemeSetting.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: const HomeScreen(),
      ),
    );
  }
}
