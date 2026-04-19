import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isLoggingOut = false;
  String? _errorMessage;

  // ── Paleta ─────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);
  static const _card = Color(0xFF252525);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _matchGreen = Color(0xFF4CAF50);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { _redirectToLogin(); return; }
      final doc = await FirebaseFirestore.instance
          .collection('usuario')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        setState(() { _userData = doc.data(); _isLoading = false; });
      } else {
        setState(() { _isLoading = false; _errorMessage = 'Perfil no encontrado.'; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Error al cargar el perfil.'; });
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cerrar sesión',
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700)),
        content: const Text('¿Estás seguro?',
            style: TextStyle(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: _pinkStart)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoggingOut = true);
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    _redirectToLogin();
  }

  Future<void> _navigateToEditProfile() async {
    final bool? ok = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => EditProfileScreen(userData: _userData!)),
    );
    if (ok == true) {
      _loadUserProfile();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('¡Perfil actualizado!'),
        backgroundColor: _matchGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _redirectToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, a, b) => const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
      (route) => false,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String get _nombreCompleto {
    final n = _userData?['nombre'] ?? '';
    final a = _userData?['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Sin nombre' : '$n $a'.trim();
  }
  String get _carrera => _userData?['carrera'] ?? 'Sin carrera';
  String get _bio => (_userData?['biografia'] as String?)?.trim().isEmpty ?? true
      ? 'Sin biografía aún'
      : _userData!['biografia'];
  String? get _fotoPerfil => _userData?['foto_perfil'];
  List<String> get _fotos => List<String>.from(_userData?['fotos'] ?? []);
  List<String> get _intereses => List<String>.from(_userData?['intereses'] ?? []);

  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _isLoading
          ? _buildLoading()
          : _errorMessage != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation(_pinkStart),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _pinkStart, size: 56),
            const SizedBox(height: 16),
            Text(_errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textSecondary, fontSize: 15)),
            const SizedBox(height: 24),
            _gradientButton('Reintentar', _loadUserProfile),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadUserProfile,
          color: _pinkStart,
          backgroundColor: _surface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildBioCard(),
                    const SizedBox(height: 12),
                    if (_intereses.isNotEmpty) _buildIntereses(),
                    const SizedBox(height: 12),
                    _buildTabBar(),
                    _buildTabContent(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_isLoggingOut)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_pinkStart)),
            ),
          ),
      ],
    );
  }

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: _bg,
      elevation: 0,
      actions: [
        _appBarIcon(Icons.edit_outlined, _navigateToEditProfile),
        _appBarIcon(Icons.logout_rounded, _isLoggingOut ? null : _handleLogout),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _buildHeader(),
      ),
    );
  }

  Widget _appBarIcon(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _pinkStart.withOpacity(0.15),
            _bg,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            _buildAvatar(),
            const SizedBox(height: 16),
            Text(
              _nombreCompleto,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_pinkStart, _orangeEnd]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _carrera,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [_pinkStart, _orangeEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _pinkStart.withOpacity(0.5),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: _fotoPerfil != null && _fotoPerfil!.isNotEmpty
            ? Image.network(
                _fotoPerfil!,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        color: _card,
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(_pinkStart),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                errorBuilder: (_, __, ___) => _defaultAvatar(),
              )
            : _defaultAvatar(),
      ),
    );
  }

  Widget _defaultAvatar() {
    return Container(
      color: _card,
      child: const Icon(Icons.person_rounded, color: Color(0xFF444444), size: 52),
    );
  }

  Widget _buildBioCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [_pinkStart, _orangeEnd],
              ).createShader(b),
              child: const Text(
                'BIOGRAFÍA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _bio,
              style: TextStyle(
                color: _bio == 'Sin biografía aún'
                    ? _textSecondary
                    : const Color(0xFFDDDDDD),
                fontSize: 14,
                height: 1.6,
                fontStyle: _bio == 'Sin biografía aún'
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntereses() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _intereses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _pinkStart.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _pinkStart.withOpacity(0.3)),
          ),
          child: Text(
            _intereses[i],
            style: const TextStyle(
                color: _pinkStart, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            gradient: const LinearGradient(colors: [_pinkStart, _orangeEnd]),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: _textSecondary,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3),
          tabs: const [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.grid_view_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('MIS FOTOS'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('REELS'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (_, __) => _tabController.index == 0
          ? _buildFotosGrid()
          : _buildEmptyTab(
              icon: Icons.videocam_outlined,
              message: 'Sin reels aún',
              sub: 'Comparte momentos en video con la comunidad',
            ),
    );
  }

  Widget _buildFotosGrid() {
    if (_fotos.isEmpty) {
      return _buildEmptyTab(
        icon: Icons.photo_library_outlined,
        message: 'Sin fotos aún',
        sub: 'Agrega fotos para que te conozcan mejor',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: _fotos.length,
        itemBuilder: (_, i) => _buildFotoItem(_fotos[i]),
      ),
    );
  }

  Widget _buildFotoItem(String url) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: _card,
            child: const Icon(Icons.broken_image_outlined,
                color: Color(0xFF444444), size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTab({
    required IconData icon,
    required String message,
    required String sub,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 32),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF333333), size: 52),
          const SizedBox(height: 12),
          Text(message,
              style: const TextStyle(
                  color: Color(0xFF555555),
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF3A3A3A), fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }

  Widget _gradientButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_pinkStart, _orangeEnd]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: _pinkStart.withOpacity(0.3),
                blurRadius: 14,
                offset: const Offset(0, 5))
          ],
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
      ),
    );
  }
}