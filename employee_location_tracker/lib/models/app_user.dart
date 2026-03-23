enum UserRole { none, employee, admin }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;
  final UserRole role;
}
