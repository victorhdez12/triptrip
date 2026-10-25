import 'package:flutter/material.dart';

const Color kPrimary = Color(0xFF29B6D2);
const Color kOrange = Color(0xFFF97316);
const Color kTeal = Color(0xFF0D9488); // hoteles (paradas de alojamiento)
const Color kBackground = Color(0xFFF5F5F5);

class AppTextField extends StatefulWidget {
  final String hint;
  final bool isPassword;
  final TextEditingController? controller;
  final TextInputType keyboardType;

  const AppTextField({
    super.key,
    required this.hint,
    this.isPassword = false,
    this.controller,
    this.keyboardType = TextInputType.text,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: widget.controller,
        obscureText: widget.isPassword ? _obscure : false,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          suffixIcon: widget.isPassword
              ? IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xFFAAAAAA),
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
        ),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = kPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class BackBtn extends StatelessWidget {
  const BackBtn({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.maybePop(context),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.chevron_left, size: 24, color: Colors.black87),
      ),
    );
  }
}

class SocialButtons extends StatelessWidget {
  const SocialButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SocialBtn(
          color: Color(0xFF1877F2),
          icon: Icons.facebook,
          iconColor: Colors.white,
        ),
        SizedBox(width: 16),
        _SocialBtn(
          gradient: LinearGradient(
            colors: [Color(0xFFF9CE34), Color(0xFFEE2A7B), Color(0xFF6228D7)],
          ),
          icon: Icons.camera_alt_outlined,
          iconColor: Colors.white,
        ),
        SizedBox(width: 16),
        _SocialBtn(
          color: kPrimary,
          icon: Icons.chat_bubble,
          iconColor: Colors.white,
        ),
        SizedBox(width: 16),
        _SocialBtn(
          color: Colors.white,
          icon: Icons.g_mobiledata,
          iconColor: Colors.red,
          border: true,
        ),
      ],
    );
  }
}

class _SocialBtn extends StatelessWidget {
  final Color? color;
  final Gradient? gradient;
  final IconData icon;
  final Color iconColor;
  final bool border;
  final VoidCallback? onTap;

  const _SocialBtn({
    this.color,
    this.gradient,
    required this.icon,
    required this.iconColor,
    this.border = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ??
          () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Social login coming soon'),
                  duration: Duration(seconds: 1),
                ),
              ),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          shape: BoxShape.circle,
          border: border ? Border.all(color: Colors.grey.shade300) : null,
        ),
        child: Icon(icon, color: iconColor, size: 26),
      ),
    );
  }
}
