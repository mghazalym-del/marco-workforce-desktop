import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../auth/user_profile.dart';

class AppState extends ChangeNotifier {
  // ===== existing date logic (keep yours) =====
  DateTime selectedDate = DateTime.now();
  String get selectedDateStr =>
      '${selectedDate.year.toString().padLeft(4, '0')}-'
      '${selectedDate.month.toString().padLeft(2, '0')}-'
      '${selectedDate.day.toString().padLeft(2, '0')}';

  void setSelectedDate(DateTime d) {
    selectedDate = d;
    notifyListeners();
  }

  // ===== auth/session =====
  String baseUrl = 'https://fireless-nontabulated-margarett.ngrok-free.dev';
  String? token;
  UserProfile? profile;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  String get role {
    // Prefer explicit role if backend provides it
    final r = profile?.role?.toUpperCase().trim();
    if (r != null && r.isNotEmpty) return r;

    // Fallback inference
    if (profile?.isSupervisor == true) return 'SUPERVISOR';
    return 'WORKER';
  }

  ApiClient? get api {
    if (!isLoggedIn) return null;
    return ApiClient(baseUrl: baseUrl, token: token!);
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('baseUrl') ?? baseUrl;
    token = prefs.getString('token');

    final profStr = prefs.getString('profile');
    if (profStr != null && profStr.isNotEmpty) {
      try {
        final m = jsonDecode(profStr) as Map<String, dynamic>;
        profile = UserProfile.fromJson(m);
      } catch (_) {
        profile = null;
      }
    }
    notifyListeners();
  }

  Future<void> saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('token', token ?? '');
    await prefs.setString('profile', profile == null ? '' : jsonEncode({
      'employee_id': profile!.employeeId,
      'full_name': profile!.fullName,
      'role': profile!.role,
      'is_supervisor': profile!.isSupervisor,
    }));
  }

  Future<void> logout() async {
    token = null;
    profile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('profile');
    notifyListeners();
  }

  void setBaseUrl(String v) {
    baseUrl = v.trim();
    notifyListeners();
    saveSession();
  }

  Future<void> login({
    required String employeeId,
  }) async {
    final tempApi = ApiClient(baseUrl: baseUrl, token: ''); // no auth needed for login
    final res = await tempApi.postJson(
      '/api/v1/auth/login',
      body: {'employee_id': employeeId.trim()},
    );

    final data = (res['data'] as Map<String, dynamic>? ) ?? {};
    final t = (data['token'] ?? '').toString();
    final p = (data['profile'] as Map<String, dynamic>? ) ?? {};

    token = t;
    profile = UserProfile.fromJson(p);
    await saveSession();
    notifyListeners();
  }
}
