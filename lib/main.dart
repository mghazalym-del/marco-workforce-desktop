import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MARCO Workforce Desktop',
      home: app.isLoggedIn ? AppShell(api: ApiClient(baseUrl: app.baseUrl, token: app.token!)) : const LoginPage(),
    );
  }
}
