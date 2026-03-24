import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.employeeName,
    required this.verificationId,
    required this.onVerified,
    required this.onResendOtp,
  });

  final String phoneNumber;
  final String employeeName;
  final String verificationId;
  final Function(UserCredential) onVerified;
  final Function() onResendOtp;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _otpDigitControllers = List.generate(6, (_) => TextEditingController());
  String? _error;
  bool _isVerifying = false;
  bool _canResend = false;
  int _resendCountdown = 60;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  @override
  void dispose() {
    for (var controller in _otpDigitControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _startResendCountdown() {
    _canResend = false;
    _resendCountdown = 60;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          _canResend = true;
        } else {
          _startResendCountdown();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final otp = _otpDigitControllers.map((c) => c.text).join();

    return WillPopScope(
      onWillPop: () async => !_isVerifying,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verify Phone Number'),
          automaticallyImplyLeading: !_isVerifying,
        ),
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
                          'Verify Your Phone',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Enter the 6-digit OTP sent to ${widget.phoneNumber}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'OTP Code',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 12),
                        _buildOtpInput(),
                        const SizedBox(height: 20),
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              border: Border.all(color: Colors.red.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(color: Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        FilledButton(
                          onPressed: _isVerifying || otp.length < 6
                              ? null
                              : () => _verifyOtp(otp),
                          child: Text(_isVerifying ? 'Verifying...' : 'Verify OTP'),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            "Didn't receive the code?",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _canResend && !_isVerifying
                              ? () {
                                  widget.onResendOtp();
                                  _startResendCountdown();
                                }
                              : null,
                          child: Text(
                            _canResend
                                ? 'Resend OTP'
                                : 'Resend in $_resendCountdown seconds',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpInput() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final fieldWidth = ((constraints.maxWidth - (spacing * 5)) / 6)
            .clamp(40.0, 56.0)
            .toDouble();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            return Padding(
              padding: EdgeInsets.only(right: index == 5 ? 0 : spacing),
              child: SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: _otpDigitControllers[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  enabled: !_isVerifying,
                  decoration: InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && value.length == 1) {
                      if (index < 5) {
                        FocusScope.of(context).nextFocus();
                      }
                    } else if (value.isEmpty && index > 0) {
                      FocusScope.of(context).previousFocus();
                    }
                    setState(() {});
                  },
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      if (mounted) {
        widget.onVerified(userCredential);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? 'Invalid OTP. Please try again.';
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Verification failed. Please try again.';
          _isVerifying = false;
        });
      }
    }
  }
}
