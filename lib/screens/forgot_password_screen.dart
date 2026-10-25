import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  Future<void> _resetPassword() async {
    if (emailCtrl.text.isEmpty) {
      _show('Introduce tu email', Colors.orange);
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: emailCtrl.text.trim(),
      );
      setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      String msg = 'Error al enviar email';
      if (e.code == 'user-not-found') msg = 'No existe cuenta con este email';
      if (e.code == 'invalid-email')  msg = 'Email no válido';
      _show(msg, Colors.redAccent);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _show(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BackBtn(),
              const SizedBox(height: 48),
              const Center(
                child: Text('Forgot password',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Enter your email to reset your password',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
                ),
              ),
              const SizedBox(height: 36),
              if (!_sent) ...[
                AppTextField(
                  hint: 'Email',
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 24),
                _loading
                    ? const Center(child: CircularProgressIndicator(color: kPrimary))
                    : AppButton(label: 'Reset Password', onPressed: _resetPassword),
              ] else ...[
                // Confirmación enviada
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: kPrimary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_outline,
                            size: 44, color: kPrimary),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Email enviado a\n${emailCtrl.text}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15, color: Color(0xFF555555)),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Revisa tu bandeja de entrada\ny sigue las instrucciones.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF999999)),
                      ),
                      const SizedBox(height: 32),
                      AppButton(
                        label: 'Volver al inicio',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}