import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/analytics_service.dart';
import '../widgets/common_widgets.dart';
import 'sign_in_screen.dart';
import 'email_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final nameCtrl  = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl  = TextEditingController();
  bool _loading = false;

  Future<void> _signUp() async {
    if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
      _show('Por favor rellena todos los campos', Colors.orange);
      return;
    }
    if (passCtrl.text.length < 8) {
      _show('La contraseña debe tener al menos 8 caracteres', Colors.orange);
      return;
    }

    setState(() => _loading = true);
    try {
      // 1. Crear cuenta en Firebase
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
      );

      // 2. Guardar nombre en el perfil
      await credential.user?.updateDisplayName(nameCtrl.text.trim());

      // 3. Enviar email de verificación (Firebase lo manda automáticamente)
      await credential.user?.sendEmailVerification();

      AnalyticsService.signUp();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(email: emailCtrl.text.trim()),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Error al crear cuenta';
      if (e.code == 'email-already-in-use') msg = 'Este email ya está registrado';
      if (e.code == 'invalid-email')        msg = 'Email no válido';
      if (e.code == 'weak-password')        msg = 'Contraseña demasiado débil';
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BackBtn(),
              const SizedBox(height: 36),
              const Center(
                child: Text('Sign up now',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text('Please fill the details and create account',
                    style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
              ),
              const SizedBox(height: 36),
              AppTextField(hint: 'Full Name', controller: nameCtrl),
              const SizedBox(height: 16),
              AppTextField(
                hint: 'Email',
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              AppTextField(hint: 'Password', isPassword: true, controller: passCtrl),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('Password must be 8 characters',
                    style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
              ),
              const SizedBox(height: 24),
              _loading
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : AppButton(label: 'Sign Up', onPressed: _signUp),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account ',
                      style: TextStyle(color: Color(0xFF999999))),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => const SignInScreen())),
                    child: const Text('Sign in',
                        style: TextStyle(color: kOrange, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Center(
                  child: Text('Or connect',
                      style: TextStyle(color: Color(0xFF999999)))),
              const SizedBox(height: 20),
              const SocialButtons(),
            ],
          ),
        ),
      ),
    );
  }
}