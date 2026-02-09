class UserProfile {
  final String employeeId;
  final String fullName;
  final String? role;
  final bool isSupervisor;

  UserProfile({
    required this.employeeId,
    required this.fullName,
    this.role,
    required this.isSupervisor,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    return UserProfile(
      employeeId: (j['employee_id'] ?? '').toString(),
      fullName: (j['full_name'] ?? j['name'] ?? '').toString(),
      role: j['role']?.toString(),
      isSupervisor: (j['is_supervisor'] == true) ||
          (j['isSupervisor'] == true) ||
          (j['is_supervisor']?.toString() == 'true'),
    );
  }
}
