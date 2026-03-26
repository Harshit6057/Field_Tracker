import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'dart:async';

const _debugOtpCode = '123456';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.employeeName,
    required this.verificationId,
    required this.onVerified,
    required this.onResendOtp,
    this.useDebugFallback = false,
    this.onDebugVerified,
  });

  final String phoneNumber;
  final String employeeName;
  final String verificationId;
  final Function(UserCredential) onVerified;
  final Future<void> Function() onResendOtp;
  final bool useDebugFallback;
  final Future<void> Function()? onDebugVerified;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> with CodeAutoFill {
  final List<TextEditingController> _otpDigitControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  String? _error;
  bool _isVerifying = false;
  bool _canResend = false;
  int _resendCountdown = 60;
  String _otp = '';
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
    listenForCode();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    cancel();
    for (var controller in _otpDigitControllers) {
      controller.dispose();
    }
    for (var focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() {
      _canResend = false;
      _resendCountdown = 60;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() {
          _resendCountdown = 0;
          _canResend = true;
        });
        return;
      }

      setState(() {
        _resendCountdown--;
      });
    });
  }

  @override
  void codeUpdated() {
    final messageCode = code;
    if (messageCode == null || messageCode.isEmpty) return;
    _fillOtpFromPaste(messageCode);
  }

  @override
  Widget build(BuildContext context) {
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
                          widget.useDebugFallback
                              ? 'Debug mode: enter $_debugOtpCode to continue.'
                              : 'Enter the 6-digit OTP sent to ${widget.phoneNumber}',
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
                          onPressed: _isVerifying || _otp.length < 6
                              ? null
                              : () => _verifyOtp(_otp),
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
                              ? () async {
                                  try {
                                    await widget.onResendOtp();
                                    if (!mounted) return;
                                    _startResendCountdown();
                                    listenForCode();
                                  } catch (_) {
                                    if (!mounted) return;
                                    setState(() {
                                      _error = 'Unable to resend OTP. Please try again.';
                                    });
                                  }
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
    const spacing = 6.0;

    return Row(
      children: [
        for (int index = 0; index < 6; index++) ...[
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    _otpDigitControllers[index].text.isEmpty &&
                    index > 0) {
                  _otpFocusNodes[index - 1].requestFocus();
                  _otpDigitControllers[index - 1].clear();
                  _updateOtp();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _otpDigitControllers[index],
                focusNode: _otpFocusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                textInputAction: index == 5 ? TextInputAction.done : TextInputAction.next,
                maxLength: 1,
                enabled: !_isVerifying,
                autofillHints: index == 0
                    ? const [AutofillHints.oneTimeCode]
                    : null,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (value) {
                  if (value.length > 1) {
                    _fillOtpFromPaste(value);
                    return;
                  }
                  if (value.isNotEmpty && index < 5) {
                    _otpFocusNodes[index + 1].requestFocus();
                  }
                  _updateOtp();
                },
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
              ),
            ),
          ),
          if (index < 5) const SizedBox(width: spacing),
        ],
      ],
    );
  }

  void _fillOtpFromPaste(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    for (int i = 0; i < 6; i++) {
      _otpDigitControllers[i].text = i < digits.length ? digits[i] : '';
    }

    final target = digits.length >= 6 ? 5 : digits.length;
    _otpFocusNodes[target.clamp(0, 5)].requestFocus();
    _updateOtp();
  }

  void _updateOtp() {
    final nextOtp = _otpDigitControllers.map((c) => c.text).join();
    if (_otp != nextOtp) {
      setState(() {
        _otp = nextOtp;
      });
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    if (widget.useDebugFallback) {
      if (otp == _debugOtpCode) {
        try {
          await widget.onDebugVerified?.call();
          if (mounted) {
            Navigator.of(context).pop();
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _error = 'Unable to complete debug sign-in. Please try again.';
              _isVerifying = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Invalid OTP. Use $_debugOtpCode in debug mode.';
            _isVerifying = false;
          });
        }
      }
      return;
    }

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
