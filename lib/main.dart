import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'auth/login_page.dart';
import 'app/app_shell.dart';
import 'api/api_client.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..loadSession(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // ✅ Desktop Theme (unchanged style)
  ThemeData _buildDesktopTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blueGrey,
      ),
      useMaterial3: true,
    );
  }

  // ✅ Web Theme (new look)
  ThemeData _buildWebTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MARCO Workforce',

      // 🔥 KEY CHANGE (safe)
      theme: kIsWeb ? _buildWebTheme() : _buildDesktopTheme(),

      home: app.isLoggedIn
          ? AppShell(
              api: ApiClient(
                baseUrl: app.baseUrl,
                token: app.token!,
              ),
            )
          : const LoginPage(),
    );
  }
}