import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../widgets/common_widgets.dart';
import 'select_language_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String phoneNumber;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.phoneNumber,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  int _secondsRemaining = 120;
  Timer? _timer;
  bool _isSending = false;
  String? _generatedOtp;

  // CREDENCIALES TWILIO - rellena estas 3 constantes:
  // 1. Regístrate gratis en https://www.twilio.com
  // 2. Copia Account SID y Auth Token de tu Dashboard
  // 3. Consigue un número en Phone Numbers > Get a number
  static const String _twilioAccountSid = 'TU_ACCOUNT_SID_AQUI';
  static const String _twilioAuthToken  = 'TU_AUTH_TOKEN_AQUI';
  static const String _twilioFrom       = '+1XXXXXXXXXX';

  @override
  void initState() {
    super.initState();
    _startTimer();
    _sendOtp();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _generateOtp() {
    final rng = Random.secure();
    return List.generate(4, (_) => rng.nextInt(10)).join();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsRemaining = 120);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsRemaining == 0) {
        t.cancel();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _sendOtp() async {
    setState(() => _isSending = true);
    _generatedOtp = _generateOtp();

    try {
      final response = await http.post(
        Uri.parse(
            'https://api.twilio.com/2010-04-01/Accounts/$_twilioAccountSid/Messages.json'),
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$_twilioAccountSid:$_twilioAuthToken'))}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'To':   widget.phoneNumber,
          'From': _twilioFrom,
          'Body': 'Tu código de verificación es: $_generatedOtp. Válido 5 min.',
        },
      );

      if (response.statusCode == 201) {
        _show('Código enviado a ${widget.phoneNumber}', kPrimary);
      } else {
        final body = jsonDecode(response.body);
        _show('Error: ${body["message"]}', Colors.redAccent);
      }
    } catch (e) {
      _show('Error de red: $e', Colors.redAccent);
    }

    setState(() => _isSending = false);
  }

  void _show(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 3) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  void _verify() {
    final entered = _controllers.map((c) => c.text).join();
    if (entered.length < 4) {
      _show('Introduce el código completo', Colors.orange);
      return;
    }
    if (_generatedOtp != null && entered == _generatedOtp) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const SelectLanguageScreen()));
    } else {
      _show('Código incorrecto', Colors.redAccent);
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    }
  }

  String get _timerText {
    final m = _secondsRemaining ~/ 60;
    final s = _secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
              const SizedBox(height: 40),
              const Center(
                child: Text('OTP Verification',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Hemos enviado un SMS a\n${widget.phoneNumber}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF999999)),
                ),
              ),
              const SizedBox(height: 36),
              const Text('OTP Code',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(4, (i) => SizedBox(
                  width: 70,
                  height: 70,
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => _onDigitChanged(i, v),
                  ),
                )),
              ),
              const SizedBox(height: 28),
              _isSending
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : AppButton(label: 'Verificar', onPressed: _verify),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _secondsRemaining == 0
                        ? () {
                            for (final c in _controllers) {
                              c.clear();
                            }
                            _startTimer();
                            _sendOtp();
                          }
                        : null,
                    child: Text(
                      'Reenviar código',
                      style: TextStyle(
                        color: _secondsRemaining == 0 ? kPrimary : const Color(0xFF999999),
                        fontWeight: _secondsRemaining == 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(_timerText,
                      style: const TextStyle(color: Color(0xFF999999))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
