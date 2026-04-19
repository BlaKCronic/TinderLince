import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ── Paleta ────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF121212);
  static const _card = Color(0xFF1E1E1E);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);
  static const _inputFill = Color(0xFF2A2A2A);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('usuario')
            .doc(user.uid)
            .set({'ultima_conexion': FieldValue.serverTimestamp()},
                SetOptions(merge: true));
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, a, b) => const ProfileScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => 'Usuario no encontrado.',
        'wrong-password' => 'Contraseña incorrecta.',
        'invalid-email' => 'Correo inválido.',
        'user-disabled' => 'Usuario deshabilitado.',
        _ => 'Error al iniciar sesión.',
      };
      if (mounted) {
        _showError(message);
      }
    } catch (_) {
      if (mounted) _showError('Error de conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
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
      body: SafeArea(
        child: FadeTransition(
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
                    const SizedBox(height: 48),
                    // ── Logo ─────────────────────────────────────────────
                    Center(child: _buildLogo()),
                    const SizedBox(height: 32),
                    // ── Título ───────────────────────────────────────────
                    Center(
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [_pinkStart, _orangeEnd],
                        ).createShader(bounds),
                        child: const Text(
                          'Lince',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'Encuentra tu match perfecto',
                        style: TextStyle(color: _textSecondary, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 44),
                    // ── Campos ───────────────────────────────────────────
                    const Text('Correo electrónico',
                        style: TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _emailController,
                      hint: 'tu@correo.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Campo requerido' : null,
                    ),
                    const SizedBox(height: 20),
                    const Text('Contraseña',
                        style: TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
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
                      validator: (v) => v == null || v.length < 6
                          ? 'Mínimo 6 caracteres'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {},
                        child: const Text('¿Olvidaste tu contraseña?',
                            style: TextStyle(color: _pinkStart, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ── Botón primario ────────────────────────────────────
                    _buildGradientButton(
                      label: 'Iniciar sesión',
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : _handleLogin,
                    ),
                    const SizedBox(height: 32),
                    // ── Divider ───────────────────────────────────────────
                    Row(children: [
                      const Expanded(child: Divider(color: Color(0xFF2E2E2E))),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('o', style: TextStyle(color: _textSecondary)),
                      ),
                      const Expanded(child: Divider(color: Color(0xFF2E2E2E))),
                    ]),
                    const SizedBox(height: 32),
                    // ── Link registro ─────────────────────────────────────
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('¿No tienes cuenta? ',
                              style: TextStyle(
                                  color: _textSecondary, fontSize: 14)),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (_, a, b) =>
                                    const RegisterScreen(),
                                transitionsBuilder: (_, anim, __, child) =>
                                    FadeTransition(
                                        opacity: anim, child: child),
                                transitionDuration:
                                    const Duration(milliseconds: 350),
                              ),
                            ),
                            child: ShaderMask(
                              shaderCallback: (b) => const LinearGradient(
                                colors: [_pinkStart, _orangeEnd],
                              ).createShader(b),
                              child: const Text(
                                'Regístrate',
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
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_pinkStart, _orangeEnd],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _pinkStart.withOpacity(0.4),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Center(
        child: Text('♥',
            style: TextStyle(color: Colors.white, fontSize: 30)),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
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
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _pinkStart, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _pinkStart),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _pinkStart, width: 1.5),
        ),
        errorStyle: const TextStyle(color: _pinkStart, fontSize: 12),
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isLoading,
  }) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: onPressed == null
            ? const LinearGradient(
                colors: [Color(0xFF555555), Color(0xFF555555)])
            : const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [_pinkStart, _orangeEnd],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: onPressed == null
            ? []
            : [
                BoxShadow(
                  color: _pinkStart.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}