import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';

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

  // Colores del tema
  static const _bgDark = Color(0xFF0A1F0A);
  static const _bgMid = Color(0xFF0F2E0F);
  static const _greenGlow = Color(0xFF6DCC6D);
  static const _greenAccent = Color(0xFF4CAF50);
  static const _cardBg = Color(0xFF152415);
  static const _tabBg = Color(0xFF1A3A1A);

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

  // ── 1. Carga de datos desde Firestore ──────────────────────────────────────
  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _redirectToLogin();
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        setState(() {
          _userData = doc.data();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No se encontró el perfil del usuario.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar el perfil. Intenta de nuevo.';
      });
    }
  }

  // ── 6. Cerrar sesión ───────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cerrar sesión',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '¿Estás seguro de que deseas cerrar sesión?',
          style: TextStyle(color: Color(0xFFB0CCB0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: _greenAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión',
                style: TextStyle(color: Colors.redAccent)),
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

  // ── Helpers de datos ───────────────────────────────────────────────────────
  String get _nombreCompleto {
    final nombre = _userData?['nombre'] ?? '';
    final apellido = _userData?['apellido'] ?? '';
    return '$nombre $apellido'.trim().isEmpty ? 'Sin nombre' : '$nombre $apellido'.trim();
  }

  String get _carrera => _userData?['carrera'] ?? 'Sin carrera';

  // ── 5. Campos opcionales con valor por defecto ─────────────────────────────
  String get _bio =>
      (_userData?['bio'] as String?)?.trim().isEmpty ?? true
          ? 'Sin biografía aún'
          : _userData!['bio'];

  String? get _fotoPerfil => _userData?['foto_perfil'];

  List<String> get _fotos =>
      List<String>.from(_userData?['fotos'] ?? []);

  List<String> get _intereses =>
      List<String>.from(_userData?['intereses'] ?? []);

  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : _buildProfileContent(),
    );
  }

  // ── 4. Estado de carga ─────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgMid, _bgDark],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_greenGlow),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Cargando perfil...',
              style: TextStyle(
                color: Color(0xFF8FC88F),
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgMid, _bgDark],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB0CCB0), fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadUserProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _greenAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text('Reintentar',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 2. Contenido principal ─────────────────────────────────────────────────
  Widget _buildProfileContent() {
    return Stack(
      children: [
        // Fondo con gradiente
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.45, 1.0],
              colors: [Color(0xFF0F3010), Color(0xFF0D250D), _bgDark],
            ),
          ),
        ),
        // Contenido scrolleable
        CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildBioCard(),
                  const SizedBox(height: 12),
                  if (_intereses.isNotEmpty) _buildInteresesRow(),
                  const SizedBox(height: 8),
                  _buildTabBar(),
                  _buildTabContent(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
        // Overlay de logout cargando
        if (_isLoggingOut)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_greenGlow),
              ),
            ),
          ),
      ],
    );
  }

  // ── App bar con foto y nombre ──────────────────────────────────────────────
  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: _bgDark,
      elevation: 0,
      actions: [
        // ── 6. Botón de cerrar sesión ──────────────────────────────────────
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white70),
          tooltip: 'Cerrar sesión',
          onPressed: _isLoggingOut ? null : _handleLogout,
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _buildProfileHeader(),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F3010), Color(0xFF0D250D)],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            // Avatar con glow
            _buildAvatar(),
            const SizedBox(height: 16),
            // Nombre
            Text(
              _nombreCompleto,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            // Carrera
            Text(
              _carrera,
              style: const TextStyle(
                color: _greenGlow,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
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
        // Glow verde como en el diseño
        boxShadow: [
          BoxShadow(
            color: _greenGlow.withOpacity(0.6),
            blurRadius: 24,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: _greenGlow.withOpacity(0.3),
            blurRadius: 48,
            spreadRadius: 8,
          ),
        ],
        border: Border.all(color: _greenGlow, width: 3),
      ),
      child: ClipOval(
        child: _fotoPerfil != null && _fotoPerfil!.isNotEmpty
            ? Image.network(
                _fotoPerfil!,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        color: _cardBg,
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(_greenGlow),
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
      color: _cardBg,
      child: const Icon(
        Icons.person_rounded,
        color: _greenGlow,
        size: 56,
      ),
    );
  }

  // ── Biografía ──────────────────────────────────────────────────────────────
  Widget _buildBioCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BIOGRAFÍA',
              style: TextStyle(
                color: _greenGlow,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _bio,
              style: TextStyle(
                color: _bio == 'Sin biografía aún'
                    ? Colors.white38
                    : const Color(0xFFD0E8D0),
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

  // ── Intereses (chips) ──────────────────────────────────────────────────────
  Widget _buildInteresesRow() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _intereses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _greenAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: _greenAccent.withOpacity(0.4), width: 1),
          ),
          child: Text(
            _intereses[i],
            style: const TextStyle(
              color: _greenGlow,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ── Tab bar ────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _tabBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: _greenGlow.withOpacity(0.5), width: 1),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: _greenGlow,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5),
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
      builder: (_, __) {
        if (_tabController.index == 0) {
          return _buildFotosGrid();
        } else {
          return _buildReelsGrid();
        }
      },
    );
  }

  // ── Grid de fotos ──────────────────────────────────────────────────────────
  Widget _buildFotosGrid() {
    final fotos = _fotos;

    if (fotos.isEmpty) {
      return _buildEmptyTab(
        icon: Icons.photo_library_outlined,
        message: 'Sin fotos aún',
        sub: 'Agrega fotos a tu perfil para que otros puedan conocerte',
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
        itemCount: fotos.length,
        itemBuilder: (_, i) => _buildFotoItem(fotos[i]),
      ),
    );
  }

  Widget _buildFotoItem(String url) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: _greenGlow.withOpacity(0.25), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : Container(
                  color: _cardBg,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_greenGlow),
                      strokeWidth: 2,
                    ),
                  ),
                ),
          errorBuilder: (_, __, ___) => Container(
            color: _cardBg,
            child: const Icon(Icons.broken_image_outlined,
                color: Colors.white24, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildReelsGrid() {
    // Los reels se manejarían igual que fotos pero con ícono de play
    // Por ahora mostramos estado vacío
    return _buildEmptyTab(
      icon: Icons.videocam_outlined,
      message: 'Sin reels aún',
      sub: 'Comparte momentos en video con la comunidad',
    );
  }

  Widget _buildEmptyTab({
    required IconData icon,
    required String message,
    required String sub,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Column(
        children: [
          Icon(icon, color: Colors.white12, size: 56),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white24,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}