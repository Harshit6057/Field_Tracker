import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_user.dart';
import 'providers/session_provider.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/employee_dashboard_screen.dart';
import 'screens/login_screen.dart';

class EmployeeLocationTrackerApp extends ConsumerWidget {
  const EmployeeLocationTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return MaterialApp(
      title: 'Office Location Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F4C81)),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: switch (session.role) {
        UserRole.admin => const AdminDashboardScreen(),
        UserRole.employee => const EmployeeDashboardScreen(),
        UserRole.none => const LoginScreen(),
      },
    );
  }
}
