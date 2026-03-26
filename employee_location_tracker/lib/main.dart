import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? bootstrapError;
  if (!AppConfig.useMockBackend) {
    try {
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          ).timeout(const Duration(seconds: 12));
        } on FirebaseException catch (error) {
          if (error.code != 'duplicate-app') {
            rethrow;
          }
        }
      }

      if (!kDebugMode) {
        try {
          await FirebaseAppCheck.instance
              .activate(
                providerAndroid: const AndroidPlayIntegrityProvider(),
                providerApple:
                    const AppleAppAttestWithDeviceCheckFallbackProvider(),
              )
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          // Keep app startup resilient when App Check is not configured yet.
        }
      }

      // Firestore rules commonly require request.auth; ensure every device has
      // a Firebase user session before the first read/write.
      try {
        await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        // Keep app startup resilient when Firebase Auth is not configured yet.
      }

      // Ensure admin login always has a default password in Firestore.
      try {
        final adminConfigRef = FirebaseFirestore.instance
            .collection('app_config')
            .doc('admin_security');
        final adminConfig = await adminConfigRef.get();
        final currentPassword = adminConfig.data()?['adminPassword'] as String?;
        if (!adminConfig.exists || currentPassword == null || currentPassword.isEmpty) {
          await adminConfigRef.set({
            'adminPassword': 'admin123',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {
        // Avoid blocking app startup if admin config bootstrap fails.
      }
    } catch (error) {
      bootstrapError = error.toString();
    }
  }

  runApp(
    ProviderScope(
      child: bootstrapError == null
          ? const EmployeeLocationTrackerApp()
          : _BootstrapErrorApp(errorMessage: bootstrapError),
    ),
  );
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.errorMessage});

  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Startup failed',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The app could not finish initializing. Check Firebase setup and network, then relaunch.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(errorMessage),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}