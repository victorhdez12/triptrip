// lib/screens/email_verification_screen.dart
//
// CAMBIO: al verificar el email redirige a OnboardingFlowScreen
// en lugar de SelectLanguageScreen.

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';
import 'onboarding_flow_screen.dart';
import 'sign_in_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({super.key, required this.email});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends State<EmailVerificationScreen> {
  Timer? _checkTimer;
  bool _resending = false;
  int _secondsResend = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startCheckTimer();
    _startResendTimer();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCheckTimer() {
    _checkTimer =
        Timer.periodic(const Duration(seconds: 3), (_) async {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified) {
        _checkTimer?.cancel();
        if (mounted) {
          // ← Ahora va al onboarding, no a SelectLanguageScreen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const OnboardingFlowScreen()),
          );
        }
      }
    });
  }

  void _startResendTimer() {
    _resendTimer =
        Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsResend == 0) {
        t.cancel();
      } else {
        setState(() => _secondsResend--);
      }
    });
  }

  Future<void> _resendEmail() async {
    setState(() => _resending = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      setState(() => _secondsResend = 60);
      _startResendTimer();
      _show('Email resent to ${widget.email}', kPrimary);
    } catch (e) {
      _show('Error resending: $e', Colors.redAccent);
    }
    setState(() => _resending = false);
  }

  Future<void> _checkManually() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.emailVerified) {
      _checkTimer?.cancel();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => const OnboardingFlowScreen()),
        );
      }
    } else {
      _show('Email not verified yet. Check your inbox.', Colors.orange);
    }
  }

  void _show(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (mounted) {
                      Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignInScreen()));
                    }
                  },
                  child: const BackBtn(),
                ),
              ),
              const Spacer(),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    size: 50, color: kPrimary),
              ),
              const SizedBox(height: 32),
              const Text(
                'Verify your email',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to:\n${widget.email}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 14, color: Color(0xFF777777)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open the email and click the link.\nThis screen will advance automatically.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
              const SizedBox(height: 40),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kPrimary),
                  ),
                  SizedBox(width: 10),
                  Text('Waiting for verification...',
                      style: TextStyle(
                          color: Color(0xFF999999), fontSize: 13)),
                ],
              ),
              const SizedBox(height: 32),
              AppButton(
                label: 'I already verified ✓',
                onPressed: _checkManually,
              ),
              const SizedBox(height: 16),
              _resending
                  ? const CircularProgressIndicator(color: kPrimary)
                  : TextButton(
                      onPressed:
                          _secondsResend == 0 ? _resendEmail : null,
                      child: Text(
                        _secondsResend == 0
                            ? 'Resend email'
                            : 'Resend in ${_secondsResend}s',
                        style: TextStyle(
                          color: _secondsResend == 0
                              ? kPrimary
                              : const Color(0xFF999999),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}