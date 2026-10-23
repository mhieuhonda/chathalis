import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'engine/app_store.dart';
import 'ui/home/home_screen.dart';

class ChatHalisApp extends StatelessWidget {
  const ChatHalisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppStore()..load(),
      child: MaterialApp(
        title: 'ChatHalis',
        debugShowCheckedModeBanner: false,
        theme: HalisTheme.light(),
        themeMode: ThemeMode.light,
        home: const HomeScreen(),
      ),
    );
  }
}
