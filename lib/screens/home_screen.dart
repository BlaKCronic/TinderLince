import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ── Paleta ─────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _matchGreen = Color(0xFF4CAF50);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  List<Map<String, dynamic>> _profiles = [];
  Map<String, String> _catalogoIntereses = {};
  bool _isLoading = true;
  int _currentIndex = 0;

  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;

  late AnimationController _snapBackController;
  late Animation<Offset> _snapBackAnimation;
  Offset _snapStartOffset = Offset.zero;

  bool _isAnimatingOut = false;
  Offset _flyOutTarget = Offset.zero;
  String? _lastAction; // 'like' | 'pass'

  @override
  void initState() {
    super.initState();
    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _snapBackAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _snapBackController,
      curve: Curves.elasticOut,
    ));
    _snapBackController.addListener(() {
      if (!_isAnimatingOut) {
        setState(() {
          _dragOffset = _snapBackAnimation.value;
        });
      }
    });
    _loadProfiles();
  }

  @override
  void dispose() {
    _snapBackController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('usuario')
            .limit(30)
            .get(),
        FirebaseFirestore.instance.collection('intereses').get(),
      ]);

      final usersSnap = results[0] as QuerySnapshot;
      final interesesSnap = results[1] as QuerySnapshot;

      final mapa = <String, String>{};
      for (final doc in interesesSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        mapa[doc.id] = data['nombre'] as String? ?? doc.id;
      }

      if (!mounted) return;
      setState(() {
        _catalogoIntereses = mapa;
        _profiles = usersSnap.docs
            .where((doc) => doc.id != currentUser.uid)
            .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isAnimatingOut) return;
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isAnimatingOut) return;
    final threshold = 90.0;
    if (_dragOffset.dx > threshold) {
      _doSwipe(like: true);
    } else if (_dragOffset.dx < -threshold) {
      _doSwipe(like: false);
    } else {
      // snap back
      _isDragging = false;
      _snapStartOffset = _dragOffset;
      _snapBackAnimation = Tween<Offset>(
        begin: _snapStartOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(
          parent: _snapBackController, curve: Curves.elasticOut));
      _snapBackController.forward(from: 0);
    }
  }

  Future<void> _doSwipe({required bool like}) async {
    if (_isAnimatingOut) return;
    _isAnimatingOut = true;
    _isDragging = false;

    final screenWidth =
        MediaQuery.of(context).size.width + 200;
    _flyOutTarget = Offset(like ? screenWidth : -screenWidth, _dragOffset.dy);

    setState(() => _lastAction = like ? 'like' : 'pass');

    // Animate card flying out
    final startOffset = _dragOffset;
    const steps = 20;
    for (int i = 1; i <= steps; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
      if (!mounted) return;
      setState(() {
        _dragOffset = Offset.lerp(startOffset, _flyOutTarget, i / steps)!;
      });
    }

    await Future.delayed(const Duration(milliseconds: 60));

    if (like) {
      _saveLike();
    }

    if (!mounted) return;
    setState(() {
      _currentIndex++;
      _dragOffset = Offset.zero;
      _isAnimatingOut = false;
      _lastAction = null;
    });
  }

  Future<void> _saveLike() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _currentIndex >= _profiles.length) return;
    final profile = _profiles[_currentIndex];
    try {
      await FirebaseFirestore.instance
          .collection('usuario')
          .doc(currentUser.uid)
          .collection('likes')
          .doc(profile['id'] as String)
          .set({'timestamp': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  double get _rotationAngle =>
      (_dragOffset.dx / 350) * 0.25;

  double get _swipeProgress =>
      (_dragOffset.dx / 120).clamp(-1.0, 1.0);

  // ── Helpers de datos ───────────────────────────────────────────────────────
  String _nombre(Map<String, dynamic> p) {
    final n = p['nombre'] ?? '';
    final a = p['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Sin nombre' : '$n $a'.trim();
  }

  String _edad(Map<String, dynamic> p) {
    final e = p['edad'];
    if (e == null) return '';
    final s = e.toString().trim();
    return s.isEmpty ? '' : s;
  }

  String _bio(Map<String, dynamic> p) {
    final b = (p['biografia'] as String?)?.trim() ?? '';
    return b.isEmpty ? '' : b;
  }

  String _carrera(Map<String, dynamic> p) =>
      (p['carrera'] as String?)?.trim() ?? '';

  String? _foto(Map<String, dynamic> p) {
    final f = p['foto_perfil'] as String?;
    return (f != null && f.isNotEmpty) ? f : null;
  }

  List<String> _intereses(Map<String, dynamic> p) {
    final ids = List<String>.from(p['intereses'] ?? []);
    return ids
        .take(4)
        .map((id) => _catalogoIntereses[id] ?? id)
        .toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildCardStack()),
            _buildActionButtons(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [_pinkStart, _orangeEnd],
            ).createShader(b),
            child: const Text(
              'Lince',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Row(
            children: [
              _topBarIcon(Icons.tune_rounded, () {}),
              const SizedBox(width: 8),
              _topBarIcon(Icons.notifications_none_rounded, () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topBarIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Icon(icon, color: _textSecondary, size: 20),
      ),
    );
  }

  Widget _buildCardStack() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(_pinkStart),
        ),
      );
    }

    if (_currentIndex >= _profiles.length) {
      return _buildEmptyState();
    }

    return LayoutBuilder(builder: (context, constraints) {
      final List<Widget> cards = [];

      // Show up to 3 cards stacked
      for (int i = (_currentIndex + 2).clamp(0, _profiles.length - 1);
          i >= _currentIndex;
          i--) {
        if (i >= _profiles.length) continue;
        final profile = _profiles[i];
        final isTop = i == _currentIndex;
        final stackPos = i - _currentIndex; // 0=top, 1=next, 2=back

        if (isTop) {
          cards.add(_buildTopCard(profile, constraints));
        } else {
          cards.add(_buildBackCard(profile, stackPos, constraints));
        }
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Stack(
          alignment: Alignment.center,
          children: cards,
        ),
      );
    });
  }

  Widget _buildTopCard(
      Map<String, dynamic> profile, BoxConstraints constraints) {
    final cardW = constraints.maxWidth;
    final cardH = constraints.maxHeight;

    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _dragOffset,
        child: Transform.rotate(
          angle: _rotationAngle,
          child: Stack(
            children: [
              _buildCardBody(profile, cardW, cardH),
              // Like stamp
              if (_swipeProgress > 0.15)
                Positioned(
                  top: 40,
                  left: 24,
                  child: _buildStamp('LIKE', _matchGreen, _swipeProgress),
                ),
              // Nope stamp
              if (_swipeProgress < -0.15)
                Positioned(
                  top: 40,
                  right: 24,
                  child: _buildStamp('NOPE', _pinkStart, -_swipeProgress),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackCard(
      Map<String, dynamic> profile, int stackPos, BoxConstraints constraints) {
    final cardW = constraints.maxWidth;
    final cardH = constraints.maxHeight;
    final scale = 1.0 - (stackPos * 0.04);
    final translateY = stackPos * 12.0;
    // As top card drags, next card scales up slightly
    final dragInfluence = (_dragOffset.dx.abs() / 150).clamp(0.0, 1.0);
    final adjustedScale =
        scale + (dragInfluence * 0.04 * (2 - stackPos).clamp(0.0, 2.0));

    return Transform.translate(
      offset: Offset(0, translateY - dragInfluence * translateY),
      child: Transform.scale(
        scale: adjustedScale,
        child: _buildCardBody(profile, cardW, cardH, dimmed: true),
      ),
    );
  }

  Widget _buildCardBody(
    Map<String, dynamic> profile,
    double cardW,
    double cardH, {
    bool dimmed = false,
  }) {
    final foto = _foto(profile);
    final nombre = _nombre(profile);
    final edad = _edad(profile);
    final bio = _bio(profile);
    final carrera = _carrera(profile);
    final intereses = _intereses(profile);

    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Foto de fondo ──────────────────────────────────────────────
            foto != null
                ? Image.network(
                    foto,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            color: _surface,
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation(_pinkStart),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                    errorBuilder: (_, __, ___) => _photoPlaceholder(),
                  )
                : _photoPlaceholder(),

            // ── Gradiente inferior ─────────────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.3),
                      Colors.black.withOpacity(0.75),
                      Colors.black.withOpacity(0.93),
                    ],
                    stops: const [0, 0.40, 0.60, 0.80, 1.0],
                  ),
                ),
              ),
            ),

            // ── Dim overlay para cards de fondo ────────────────────────────
            if (dimmed)
              Positioned.fill(
                child: Container(
                  color: _bg.withOpacity(0.15),
                ),
              ),

            // ── Info ───────────────────────────────────────────────────────
            Positioned(
              left: 22,
              right: 22,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre + edad
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      if (edad.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          edad,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Carrera
                  if (carrera.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.school_outlined,
                            color: _pinkStart, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          carrera,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Bio
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                  // Intereses
                  if (intereses.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: intereses
                          .map((int) => _interesChip(int))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),

            // ── Indicador de distancia swipe (barra superior) ──────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                child: LinearProgressIndicator(
                  value: 0,
                  backgroundColor: Colors.transparent,
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: _surface,
      child: Center(
        child: Icon(Icons.person_rounded,
            color: Colors.white.withOpacity(0.15), size: 100),
      ),
    );
  }

  Widget _interesChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStamp(String label, Color color, double opacity) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_pinkStart.withOpacity(0.15), _orangeEnd.withOpacity(0.1)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.favorite_border_rounded,
                color: _pinkStart.withOpacity(0.6), size: 44),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sin más perfiles',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Vuelve más tarde para descubrir\nnuevas personas',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () => setState(() {
              _currentIndex = 0;
              _loadProfiles();
            }),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_pinkStart, _orangeEnd]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _pinkStart.withOpacity(0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Text(
                'Actualizar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final hasProfiles = _currentIndex < _profiles.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Rewind (pequeño)
          _actionButton(
            icon: Icons.replay_rounded,
            size: 48,
            iconSize: 22,
            gradient: null,
            color: _surface,
            iconColor: _orangeEnd,
            onTap: hasProfiles && _currentIndex > 0
                ? () => setState(() {
                      _currentIndex--;
                      _dragOffset = Offset.zero;
                    })
                : null,
          ),
          // Nope (grande)
          _actionButton(
            icon: Icons.close_rounded,
            size: 64,
            iconSize: 32,
            gradient: null,
            color: _surface,
            iconColor: _pinkStart,
            onTap: hasProfiles ? () => _doSwipe(like: false) : null,
          ),
          // Like (grande)
          _actionButton(
            icon: Icons.favorite_rounded,
            size: 64,
            iconSize: 30,
            gradient: const LinearGradient(colors: [_pinkStart, _orangeEnd]),
            color: null,
            iconColor: Colors.white,
            onTap: hasProfiles ? () => _doSwipe(like: true) : null,
          ),
          // Super like (pequeño)
          _actionButton(
            icon: Icons.star_rounded,
            size: 48,
            iconSize: 22,
            gradient: null,
            color: _surface,
            iconColor: const Color(0xFF64B5F6),
            onTap: hasProfiles ? () => _doSwipe(like: true) : null,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required Gradient? gradient,
    required Color? color,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: gradient,
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (gradient != null ? _pinkStart : Colors.black)
                  .withOpacity(gradient != null ? 0.35 : 0.25),
              blurRadius: gradient != null ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: color != null
              ? Border.all(color: Colors.white.withOpacity(0.07))
              : null,
        ),
        child: Icon(icon, color: iconColor.withOpacity(onTap != null ? 1.0 : 0.3), size: iconSize),
      ),
    );
  }
}