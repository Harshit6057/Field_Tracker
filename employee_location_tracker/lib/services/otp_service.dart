import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';

class OtpService {
  static const String _otpCollection = 'otp_requests';
  static const int _otpExpiryMinutes = 10;
  static const int _otpLength = 6;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generate and send OTP for a phone number
  Future<String> generateAndSendOtp({required String phoneNumber}) async {
    try {
      // Generate 6-digit OTP
      final otp = _generateOtp();

      // Store in Firestore with expiry timestamp
      final expiryTime = DateTime.now().add(Duration(minutes: _otpExpiryMinutes));

      await _firestore.collection(_otpCollection).doc(phoneNumber).set({
        'otp': otp,
        'phoneNumber': phoneNumber,
        'createdAt': FieldValue.serverTimestamp(),
        'expiryTime': Timestamp.fromDate(expiryTime),
        'attempts': 0,
        'verified': false,
      });

      if (kDebugMode) {
        debugPrint('OTP generated for $phoneNumber: $otp (Debug only)');
      }
      return otp; // Return for debug display in dev mode
    } catch (e) {
      throw Exception('Failed to generate OTP: $e');
    }
  }

  /// Verify OTP and return true if valid
  Future<bool> verifyOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    try {
      final docRef = _firestore.collection(_otpCollection).doc(phoneNumber);
      final doc = await docRef.get();

      if (!doc.exists) {
        throw Exception('No OTP request found for this phone number');
      }

      final data = doc.data() as Map<String, dynamic>;

      // Check if expired
      final expiryTime = (data['expiryTime'] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiryTime)) {
        await docRef.delete();
        throw Exception('OTP has expired. Please request a new one.');
      }

      // Check if already verified
      if (data['verified'] == true) {
        throw Exception('OTP has already been used.');
      }

      // Check attempt limit
      int attempts = data['attempts'] ?? 0;
      if (attempts >= 5) {
        await docRef.delete();
        throw Exception('Too many failed attempts. Please request a new OTP.');
      }

      // Verify OTP
      if (data['otp'] != otp) {
        // Increment attempts
        await docRef.update({'attempts': attempts + 1});
        throw Exception('Invalid OTP. Please try again.');
      }

      // Mark as verified
      await docRef.update({'verified': true});
      return true;
    } catch (e) {
      rethrow;
    }
  }

  /// Clean up verified OTP documents
  Future<void> cleanupOtp(String phoneNumber) async {
    try {
      await _firestore.collection(_otpCollection).doc(phoneNumber).delete();
    } catch (_) {
      // Silently ignore cleanup errors
    }
  }

  /// Generate random 6-digit OTP
  String _generateOtp() {
    final random = Random();
    return List.generate(_otpLength, (_) => random.nextInt(10)).join('');
  }

  /// Resend OTP (generates new one)
  Future<String> resendOtp({required String phoneNumber}) async {
    await cleanupOtp(phoneNumber);
    return generateAndSendOtp(phoneNumber: phoneNumber);
  }
}
