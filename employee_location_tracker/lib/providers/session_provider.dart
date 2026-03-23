import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';

class SessionState {
  const SessionState({
    required this.role,
    this.employeeId,
    this.employeeName,
    this.employeePhone,
  });

  final UserRole role;
  final String? employeeId;
  final String? employeeName;
  final String? employeePhone;

  static const loggedOut = SessionState(role: UserRole.none);
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier() : super(SessionState.loggedOut);

  void loginAsAdmin() {
    state = const SessionState(role: UserRole.admin);
  }

  void loginAsEmployee({
    required String employeeId,
    required String employeeName,
    required String employeePhone,
  }) {
    state = SessionState(
      role: UserRole.employee,
      employeeId: employeeId,
      employeeName: employeeName,
      employeePhone: employeePhone,
    );
  }

  void logout() {
    state = SessionState.loggedOut;
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier();
});
