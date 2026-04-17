import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'edit_profile_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _acceptTerms = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ── Paleta ────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF121212);
  static const _inputFill = Color(0xFF2A2A2A);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Map<String, String> _splitNombre(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return {'nombre': parts[0], 'apellido': ''};
    return {'nombre': parts.first, 'apellido': parts.sublist(1).join(' ')};
  }

  Future<void> _handleRegister() async {
    if (!_acceptTerms) {
      _showSnack('Acepta los Términos y Condiciones para continuar');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final nombreData = _splitNombre(_nombreController.text);
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = credential.user;
      if (user != null) {
        final initialData = {
          'nombre': nombreData['nombre'],
          'apellido': nombreData['apellido'],
          'email_institucional': _emailController.text.trim(),
          'fecha_registro': FieldValue.serverTimestamp(),
          'ultima_conexion': FieldValue.serverTimestamp(),
          'activo': true,
          'fotos': <String>[],
          'intereses': <String>[],
          'genero': <String>[],
          'biografia': '',
          'carrera': '',
          'edad': '',
          'foto_perfil': '',
        };
        await FirebaseFirestore.instance
            .collection('usuario')
            .doc(user.uid)
            .set(initialData);

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, a, b) => EditProfileScreen(
              userData: {
                'nombre': nombreData['nombre'],
                'apellido': nombreData['apellido'],
                'biografia': '',
                'carrera': '',
                'foto_perfil': '',
                'intereses': <String>[],
              },
              isNewUser: true,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'email-already-in-use' => 'Este correo ya está registrado.',
        'weak-password' => 'Contraseña muy débil (mín. 8 chars).',
        'invalid-email' => 'Correo inválido.',
        _ => 'Error al crear la cuenta.',
      };
      if (mounted) _showSnack(message);
    } catch (_) {
      if (mounted) _showSnack('Error de conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _pinkStart,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [_pinkStart, _orangeEnd],
                    ).createShader(b),
                    child: const Text(
                      'Crear cuenta',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Únete y empieza a conectar',
                    style: TextStyle(color: _textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 36),
                  _fieldLabel('Nombre completo'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _nombreController,
                    hint: 'Juan Pérez',
                    icon: Icons.person_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Campo requerido';
                      if (v.trim().split(' ').length < 2)
                        return 'Ingresa nombre y apellido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel('Correo electrónico'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _emailController,
                    hint: 'tu@correo.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Campo requerido';
                      final re = RegExp(
                          r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                      if (!re.hasMatch(v)) return 'Correo inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel('Contraseña'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _passwordController,
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _textSecondary,
                        size: 20,
                      ),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Campo requerido';
                      if (v.length < 8) return 'Mínimo 8 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  _buildTermsRow(),
                  const SizedBox(height: 28),
                  _buildGradientButton(),
                  const SizedBox(height: 32),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('¿Ya tienes cuenta? ',
                            style:
                                TextStyle(color: _textSecondary, fontSize: 14)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: ShaderMask(
                            shaderCallback: (b) => const LinearGradient(
                              colors: [_pinkStart, _orangeEnd],
                            ).createShader(b),
                            child: const Text(
                              'Inicia sesión',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(label,
        style: const TextStyle(
            color: _textSecondary, fontSize: 13, fontWeight: FontWeight.w500));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: const TextStyle(color: _textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 15),
        prefixIcon: Icon(icon, color: _textSecondary, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF2E2E2E))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _pinkStart, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _pinkStart)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _pinkStart, width: 1.5)),
        errorStyle: const TextStyle(color: _pinkStart, fontSize: 12),
      ),
    );
  }

  Widget _buildTermsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => setState(() => _acceptTerms = !_acceptTerms),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              gradient: _acceptTerms
                  ? const LinearGradient(
                      colors: [_pinkStart, _orangeEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)
                  : null,
              color: _acceptTerms ? null : _inputFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _acceptTerms ? Colors.transparent : const Color(0xFF444444),
                  width: 1.5),
            ),
            child: _acceptTerms
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: _textSecondary, fontSize: 13),
              children: [
                const TextSpan(text: 'Acepto los '),
                WidgetSpan(
                  child: GestureDetector(
                    onTap: () {},
                    child: const Text(
                      'Términos y Condiciones',
                      style: TextStyle(
                        color: _pinkStart,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGradientButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: _isLoading
            ? const LinearGradient(colors: [Color(0xFF555555), Color(0xFF555555)])
            : const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [_pinkStart, _orangeEnd]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isLoading
            ? []
            : [
                BoxShadow(
                  color: _pinkStart.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _isLoading ? null : _handleRegister,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Text(
                    'Crear cuenta',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5),
                  ),
          ),
        ),
      ),
    );
  }
}