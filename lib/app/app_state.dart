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

  // ✅ Always non-null ApiClient (no more ApiClient? crash)
  late ApiClient api = ApiClient(baseUrl: baseUrl, token: token);

  bool get isLoggedIn => (token != null && token!.isNotEmpty);

  String get role {
    final r = profile?.role?.toUpperCase().trim();
    if (r != null && r.isNotEmpty) return r;
    if (profile?.isSupervisor == true) return 'SUPERVISOR';
    return 'WORKER';
  }

  void _rebuildApi() {
    api = ApiClient(baseUrl: baseUrl, token: token);
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

    _rebuildApi();
    notifyListeners();
  }

  Future<void> saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('token', token ?? '');
    await prefs.setString(
      'profile',
      profile == null
          ? ''
          : jsonEncode({
              'employee_id': profile!.employeeId,
              'full_name': profile!.fullName,
              'role': profile!.role,
              'is_supervisor': profile!.isSupervisor,
            }),
    );
  }

  Future<void> logout() async {
    token = null;
    profile = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('profile');

    _rebuildApi();
    notifyListeners();
  }

  void setBaseUrl(String v) {
    baseUrl = v.trim();
    _rebuildApi();
    notifyListeners();
    saveSession();
  }

  // -------------------------
  // Robust login parsing
  // -------------------------
  Future<void> login({required String employeeId}) async {
    final tempApi = ApiClient(baseUrl: baseUrl, token: null);

    // Keep your backend path as-is (ngrok shows it works)
    final res = await tempApi.postJson(
      '/api/v1/auth/login',
      body: {'employee_id': employeeId.trim()},
    );

    // res might be:
    // 1) {success:true, data:{token, profile/employee}}
    // 2) {token, profile/employee}   (if api_client unwraps)
    final root = (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};

    final dynamic dataNode = root['data'];
    final data = (dataNode is Map)
        ? Map<String, dynamic>.from(dataNode)
        : root;

    final t = (data['token'] ?? root['token'] ?? '').toString();

    // profile could be named profile / employee / user
    final dynamic profileNode =
        data['profile'] ?? data['employee'] ?? data['user'] ?? root['profile'] ?? root['employee'] ?? root['user'];

    final p = (profileNode is Map)
        ? Map<String, dynamic>.from(profileNode)
        : <String, dynamic>{};

    token = t;
    profile = p.isNotEmpty ? UserProfile.fromJson(p) : null;

    // If backend doesn’t return profile but token exists, still allow login.
    // (Some systems return token only.)
    if (token == null || token!.isEmpty) {
      throw Exception('Login OK but token missing. Response: $root');
    }

    _rebuildApi();
    await saveSession();
    notifyListeners();
  }
}
