import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/session_provider.dart';
import '../providers/tracking_provider.dart';
import 'otp_verification_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isAdmin = false;
  final _employeeNameController = TextEditingController();
  final _employeePhoneController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _adminPasscodeController = TextEditingController();
  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _employeeNameController.dispose();
    _employeePhoneController.dispose();
    _adminNameController.dispose();
    _adminPasscodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Office Location Tracker',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Secure check-in, check-out and live route visibility for admin.',
                      ),
                      const SizedBox(height: 20),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, label: Text('Employee')),
                          ButtonSegment(value: true, label: Text('Admin')),
                        ],
                        selected: {_isAdmin},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _isAdmin = selection.first;
                            _error = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_isAdmin) ...[
                        TextField(
                          controller: _adminNameController,
                          decoration: const InputDecoration(
                            labelText: 'Admin name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _adminPasscodeController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Admin passcode',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _employeeNameController,
                          decoration: const InputDecoration(
                            labelText: 'Employee name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _employeePhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Employee phone number',
                            hintText: '10-digit phone or +91XXXXXXXXXX',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: Text(_isAdmin ? 'Continue as Admin' : 'Continue as Employee'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final repository = ref.read(trackingRepositoryProvider);

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      if (_isAdmin) {
        final adminName = _adminNameController.text.trim();
        if (adminName.isEmpty) {
          setState(() {
            _error = 'Admin name is required.';
          });
          return;
        }
        final isValid = await repository.validateAdminPassword(
          _adminPasscodeController.text.trim(),
        );
        if (!isValid) {
          setState(() {
            _error = 'Invalid admin password.';
          });
          return;
        }
        sessionNotifier.loginAsAdmin(adminName: adminName);
        return;
      }

      final employeeName = _employeeNameController.text.trim();
      final phoneNumber = _employeePhoneController.text.trim();
      if (employeeName.isEmpty || phoneNumber.isEmpty) {
        setState(() {
          _error = 'Employee name and phone number are required.';
        });
        return;
      }

      // Send OTP via Firebase
      await _sendOtp(employeeName, phoneNumber);
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _sendOtp(String employeeName, String phoneNumber) async {
    try {
      // Format phone number with country code if not already present
      String formattedPhone = phoneNumber.startsWith('+') ? phoneNumber : '+91$phoneNumber';

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification (only works on Android with Google Play Services)
          await _completeEmployeeLogin(employeeName, phoneNumber);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              final message = e.message ?? 'Phone verification failed.';
              if (message.toLowerCase().contains('missing a valid app identifier')) {
                _error = 'Phone auth blocked by app verification. Add SHA-1 and SHA-256 for com.example.sales_tracking_app in Firebase Android app settings, then download latest google-services.json and retry.';
              } else {
                _error = message;
              }
            });
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            _navigateToOtpScreen(employeeName, phoneNumber, verificationId);
          }
        },
        codeAutoRetrievalTimeout: (_) {},
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to send OTP: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _completeEmployeeLogin(
    String employeeName,
    String phoneNumber,
  ) async {
    final repository = ref.read(trackingRepositoryProvider);
    final sessionNotifier = ref.read(sessionProvider.notifier);

    try {
      // Firebase authentication successful, now create/update employee profile
      final employee = await repository.upsertEmployeeProfile(
        employeeName: employeeName,
        phoneNumber: phoneNumber,
      );

      sessionNotifier.loginAsEmployee(
        employeeId: employee.employeeId,
        employeeName: employee.employeeName,
        employeePhone: employee.phoneNumber ?? phoneNumber,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Failed to complete login: ${error.toString()}';
        });
      }
    }
  }

  void _navigateToOtpScreen(
    String employeeName,
    String phoneNumber,
    String verificationId,
    {bool useDebugFallback = false}
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OtpVerificationScreen(
          phoneNumber: phoneNumber,
          employeeName: employeeName,
          verificationId: verificationId,
          useDebugFallback: useDebugFallback,
          onDebugVerified: useDebugFallback
              ? () => _completeEmployeeLogin(employeeName, phoneNumber)
              : null,
          onVerified: (UserCredential credential) async {
            // OTP verified, complete employee login
            if (mounted) {
              Navigator.of(context).pop();
            }
            await _completeEmployeeLogin(employeeName, phoneNumber);
          },
          onResendOtp: () async {
            // Resend OTP
            await _sendOtp(employeeName, phoneNumber);
          },
        ),
      ),
    );
  }
}
