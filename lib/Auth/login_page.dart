import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
import '../app/app_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final empCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  bool loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      urlCtrl.text = app.baseUrl;
      setState(() {});
    });
  }

  Future<void> _doLogin() async {
    final app = context.read<AppState>();
    final emp = empCtrl.text.trim();

    if (emp.isEmpty) {
      await _popup('Validation', 'Please enter employee_id (e.g., E2001).');
      return;
    }

    setState(() => loading = true);
    try {
      final url = urlCtrl.text.trim();
      if (url.isNotEmpty && url != app.baseUrl) {
        app.setBaseUrl(url);
      }

      await app.login(employeeId: emp);

      if (!mounted) return;

      // ✅ Now AppState.api is ALWAYS non-null
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShell(api: app.api),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logged in as ${app.profile?.employeeId ?? emp}')),
      );
    } catch (e) {
      await _popup('Login failed', e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _popup(String title, String msg) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    empCtrl.dispose();
    urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MARCO Workforce Desktop — Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Backend Base URL',
                    hintText: 'https://xxxxx.ngrok-free.dev',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: empCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Employee ID',
                    hintText: 'E2001',
                  ),
                  onSubmitted: (_) => _doLogin(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : _doLogin,
                    child: Text(loading ? 'Logging in...' : 'Login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
