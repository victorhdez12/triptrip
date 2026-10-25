import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';
import 'sign_up_screen.dart';
import 'forgot_password_screen.dart';
import 'select_language_screen.dart';
import 'email_verification_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl  = TextEditingController();
  bool _loading = false;

  Future<void> _signIn() async {
    if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
      _show('Por favor rellena todos los campos', Colors.orange);
      return;
    }
    setState(() => _loading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
      );

      if (!mounted) return;

      // Si el email no está verificado, lo mandamos a verificar
      if (credential.user != null && !credential.user!.emailVerified) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(email: emailCtrl.text.trim()),
          ),
        );
        return;
      }

      // Email verificado → entrar a la app
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SelectLanguageScreen()),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'Error al iniciar sesión';
      if (e.code == 'user-not-found')  msg = 'No existe cuenta con este email';
      if (e.code == 'wrong-password')  msg = 'Contraseña incorrecta';
      if (e.code == 'invalid-email')   msg = 'Email no válido';
      if (e.code == 'user-disabled')   msg = 'Cuenta desactivada';
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
                child: Text('Sign in now',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text('Please sign in to continue our app',
                    style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
              ),
              const SizedBox(height: 36),
              AppTextField(
                hint: 'Email',
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              AppTextField(hint: 'Password', isPassword: true, controller: passCtrl),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                  child: const Text('Forget Password?',
                      style: TextStyle(color: kOrange, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              _loading
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : AppButton(label: 'Sign In', onPressed: _signIn),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ",
                      style: TextStyle(color: Color(0xFF999999))),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SignUpScreen())),
                    child: const Text('Sign up',
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