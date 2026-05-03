import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'user_profile_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers globales para likes/matches (reutilizables desde búsqueda, home, etc.)
// ═══════════════════════════════════════════════════════════════════════════════

/// Guarda un like y, si hay like inverso, crea el match.
/// Devuelve el matchId si se creó match, null si solo se dio like.
Future<String?> sendLikeAndMaybeMatch({
  required String fromUserId,
  required String toUserId,
}) async {
  if (fromUserId.isEmpty || toUserId.isEmpty || fromUserId == toUserId) {
    return null;
  }
  try {
    final docId = '${fromUserId}_$toUserId';
    await FirebaseFirestore.instance.collection('likes').doc(docId).set({
      'from': fromUserId,
      'to': toUserId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    final reverseDocId = '${toUserId}_$fromUserId';
    final reverseDoc = await FirebaseFirestore.instance
        .collection('likes')
        .doc(reverseDocId)
        .get();

    if (reverseDoc.exists) {
      final ids = [fromUserId, toUserId]..sort();
      final matchId = '${ids[0]}_${ids[1]}';
      await FirebaseFirestore.instance.collection('matches').doc(matchId).set({
        // FIX: guardamos `users` en orden estable (alfabético, igual que el
        // matchId). Antes se guardaba [fromUserId, toUserId] y cada
        // sobreescritura del documento (al re-escribirse en otros flujos)
        // invertía el orden, haciendo que MatchesScreen confundiera quién
        // era "el otro usuario" — los chats parecían cambiar de dueño.
        'users': ids,
        'timestamp': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageTime': null,
        'lastMessageSender': null,
      }, SetOptions(merge: true));
      return matchId;
    }
    return null;
  } catch (e) {
    debugPrint('Error en sendLikeAndMaybeMatch: $e');
    return null;
  }
}

/// Verifica si el usuario actual ya dio like a otro usuario.
Future<bool> hasLiked({
  required String fromUserId,
  required String toUserId,
}) async {
  if (fromUserId.isEmpty || toUserId.isEmpty) return false;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('likes')
        .doc('${fromUserId}_$toUserId')
        .get();
    return doc.exists;
  } catch (_) {
    return false;
  }
}

/// Helper de migración. Llamar UNA VEZ con un usuario logueado para corregir
/// los documentos existentes en `matches/` que tienen el campo `users`
/// desordenado. Después de ejecutar, este método se puede eliminar.
///
/// Uso recomendado: añadir un botón temporal en alguna pantalla de admin
/// y llamarlo. Una vez todos los matches están bien, borra esta función.
Future<void> fixMatchesUsersOrder() async {
  final snap = await FirebaseFirestore.instance.collection('matches').get();
  int fixed = 0;
  for (final doc in snap.docs) {
    final data = doc.data();
    final users = List<String>.from(data['users'] ?? []);
    if (users.length == 2) {
      final sorted = [...users]..sort();
      if (sorted[0] != users[0] || sorted[1] != users[1]) {
        await doc.reference.update({'users': sorted});
        fixed++;
        debugPrint('Fixed match ${doc.id}');
      }
    }
  }
  debugPrint('fixMatchesUsersOrder: $fixed documentos corregidos.');
}

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

  ProfileFilters _currentFilters = ProfileFilters();

  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;

  late AnimationController _snapBackController;
  late Animation<Offset> _snapBackAnimation;
  Offset _snapStartOffset = Offset.zero;

  bool _isAnimatingOut = false;
  Offset _flyOutTarget = Offset.zero;
  String? _lastAction;

  // ── Match overlay ───────────────────────────────────────────────────────────
  bool _showMatchOverlay = false;
  Map<String, dynamic>? _matchedProfile;
  String? _lastMatchId;

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

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
    _fetchProfiles();
  }

  @override
  void dispose() {
    _snapBackController.dispose();
    super.dispose();
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
    const threshold = 90.0;
    if (_dragOffset.dx > threshold) {
      _doSwipe(like: true);
    } else if (_dragOffset.dx < -threshold) {
      _doSwipe(like: false);
    } else {
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

    final screenWidth = MediaQuery.of(context).size.width + 200;
    _flyOutTarget = Offset(like ? screenWidth : -screenWidth, _dragOffset.dy);

    setState(() => _lastAction = like ? 'like' : 'pass');

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
      await _saveLikeAndCheckMatch();
    }

    if (!mounted) return;
    setState(() {
      _currentIndex++;
      _dragOffset = Offset.zero;
      _isAnimatingOut = false;
      _lastAction = null;
    });
  }

  // ── Like + detección de match ───────────────────────────────────────────────
  Future<void> _saveLikeAndCheckMatch() async {
    if (_currentUserId.isEmpty || _currentIndex >= _profiles.length) return;
    final profile = _profiles[_currentIndex];
    final String toUserId = profile['id'] as String;
    final String fromUserId = _currentUserId;

    final matchId = await sendLikeAndMaybeMatch(
      fromUserId: fromUserId,
      toUserId: toUserId,
    );

    if (matchId != null && mounted) {
      _showMatch(profile, matchId);
    }
  }

  void _showMatch(Map<String, dynamic> profile, String matchId) {
    setState(() {
      _matchedProfile = profile;
      _showMatchOverlay = true;
      _lastMatchId = matchId;
    });
  }

  void _closeMatchOverlay() {
    setState(() {
      _showMatchOverlay = false;
      _matchedProfile = null;
      // FIX: reseteamos _lastMatchId al cerrar el overlay para evitar
      // que un matchId viejo se quede colgado en el State si el usuario
      // hace otro match sin navegar al chat.
      _lastMatchId = null;
    });
  }

  void _navigateToChat() {
    // Capturamos los valores ANTES de cerrar el overlay (que los limpia).
    final matchId = _lastMatchId;
    final profile = _matchedProfile;

    _closeMatchOverlay();

    if (matchId == null || profile == null) return;

    final nombre = _nombre(profile);
    final foto = _foto(profile);
    final otherId = profile['id'] as String;

    Navigator.push(
      context,
      PageRouteBuilder(
        // FIX: ValueKey amarrada al matchId. Asegura que Flutter nunca
        // reutilice el State (controllers, focus, listeners) entre
        // chats distintos.
        pageBuilder: (_, a, b) => ChatScreen(
          key: ValueKey('chat_$matchId'),
          matchId: matchId,
          otherUserId: otherId,
          otherUserName: nombre,
          otherUserPhoto: foto,
        ),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  // ── Swipe angles ────────────────────────────────────────────────────────────
  double get _rotationAngle => (_dragOffset.dx / 350) * 0.25;
  double get _swipeProgress => (_dragOffset.dx / 120).clamp(-1.0, 1.0);

  // ── Helpers de datos ────────────────────────────────────────────────────────
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
    return ids.take(4).map((id) => _catalogoIntereses[id] ?? id).toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildCardStack()),
                _buildActionButtons(),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (_showMatchOverlay && _matchedProfile != null)
            _MatchOverlay(
              profile: _matchedProfile!,
              onClose: _closeMatchOverlay,
              onMessage: _navigateToChat,
            ),
        ],
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
              _topBarIcon(Icons.search_rounded, () => _showSearchModal()),
              const SizedBox(width: 8),
              _topBarIcon(Icons.tune_rounded, () => _showFilterModal()),
              const SizedBox(width: 8),
              _buildNotificationsIcon(),
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

  /// Ícono de notificaciones (campana) con badge en vivo de likes recibidos.
  Widget _buildNotificationsIcon() {
    final likesStream = FirebaseFirestore.instance
        .collection('likes')
        .where('to', isEqualTo: _currentUserId)
        .snapshots();

    final userDocStream = _currentUserId.isEmpty
        ? const Stream<DocumentSnapshot>.empty()
        : FirebaseFirestore.instance
            .collection('usuario')
            .doc(_currentUserId)
            .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: userDocStream,
      builder: (context, userSnap) {
        Timestamp? lastSeen;
        if (userSnap.hasData && userSnap.data!.exists) {
          final data = userSnap.data!.data() as Map<String, dynamic>?;
          lastSeen = data?['lastLikesSeen'] as Timestamp?;
        }
        return StreamBuilder<QuerySnapshot>(
          stream: likesStream,
          builder: (context, likesSnap) {
            int unseenCount = 0;
            if (likesSnap.hasData) {
              final docs = likesSnap.data!.docs;
              unseenCount = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final ts = data['timestamp'] as Timestamp?;
                if (ts == null) return false;
                if (lastSeen == null) return true;
                return ts.compareTo(lastSeen) > 0;
              }).length;
            }

            return GestureDetector(
              onTap: _showLikesReceivedModal,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Icon(
                      unseenCount > 0
                          ? Icons.notifications_rounded
                          : Icons.notifications_none_rounded,
                      color:
                          unseenCount > 0 ? _pinkStart : _textSecondary,
                      size: 20,
                    ),
                  ),
                  if (unseenCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: unseenCount > 9 ? 5 : 0,
                          vertical: 2,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_pinkStart, _orangeEnd],
                          ),
                          shape: unseenCount > 9
                              ? BoxShape.rectangle
                              : BoxShape.circle,
                          borderRadius: unseenCount > 9
                              ? BorderRadius.circular(9)
                              : null,
                          border: Border.all(color: _bg, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: _pinkStart.withOpacity(0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            unseenCount > 99 ? '99+' : '$unseenCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Abre el modal de likes recibidos y marca todos como vistos.
  Future<void> _showLikesReceivedModal() async {
    if (_currentUserId.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('usuario')
          .doc(_currentUserId)
          .set(
        {'lastLikesSeen': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _LikesReceivedSheet(
        currentUserId: _currentUserId,
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

      for (int i = (_currentIndex + 2).clamp(0, _profiles.length - 1);
          i >= _currentIndex;
          i--) {
        if (i >= _profiles.length) continue;
        final profile = _profiles[i];
        final isTop = i == _currentIndex;
        final stackPos = i - _currentIndex;

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
              if (_swipeProgress > 0.15)
                Positioned(
                  top: 40,
                  left: 24,
                  child: _buildStamp('LIKE', _matchGreen, _swipeProgress),
                ),
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
                    errorBuilder: (_, _, _) => _photoPlaceholder(),
                  )
                : _photoPlaceholder(),
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
            if (dimmed)
              Positioned.fill(
                child: Container(color: _bg.withOpacity(0.15)),
              ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  if (intereses.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          intereses.map((i) => _interesChip(i)).toList(),
                    ),
                  ],
                ],
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
                colors: [
                  _pinkStart.withOpacity(0.15),
                  _orangeEnd.withOpacity(0.1)
                ],
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
              _fetchProfiles();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
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
          _actionButton(
            icon: Icons.close_rounded,
            size: 64,
            iconSize: 32,
            gradient: null,
            color: _surface,
            iconColor: _pinkStart,
            onTap: hasProfiles ? () => _doSwipe(like: false) : null,
          ),
          _actionButton(
            icon: Icons.favorite_rounded,
            size: 64,
            iconSize: 30,
            gradient:
                const LinearGradient(colors: [_pinkStart, _orangeEnd]),
            color: null,
            iconColor: Colors.white,
            onTap: hasProfiles ? () => _doSwipe(like: true) : null,
          ),
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
        child: Icon(icon,
            color: iconColor.withOpacity(onTap != null ? 1.0 : 0.3),
            size: iconSize),
      ),
    );
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                  left: 28,
                  right: 28,
                  top: 15,
                  bottom: MediaQuery.of(context).padding.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Center(
                    child: Text("AJUSTES DE BÚSQUEDA",
                        style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5)),
                  ),
                  const SizedBox(height: 30),
                  _buildSectionHeader("Rango de Edad",
                      "${_currentFilters.minEdad} - ${_currentFilters.maxEdad}"),
                  RangeSlider(
                    values: RangeValues(_currentFilters.minEdad.toDouble(),
                        _currentFilters.maxEdad.toDouble()),
                    min: 18,
                    max: 60,
                    activeColor: _pinkStart,
                    inactiveColor: Colors.white12,
                    onChanged: (values) {
                      setModalState(() {
                        _currentFilters.minEdad = values.start.round();
                        _currentFilters.maxEdad = values.end.round();
                      });
                    },
                  ),
                  const Divider(color: Colors.white10, height: 40),
                  _buildSectionHeader(
                      "Carrera",
                      _currentFilters.carreras.isEmpty
                          ? "Todas"
                          : _currentFilters.carreras.join(", ")),
                  const SizedBox(height: 12),
                  _buildCarrerasSelector(setModalState),
                  const Divider(color: Colors.white10, height: 40),
                  _buildSectionHeader("Intereses",
                      "${_currentFilters.intereses.length} seleccionados"),
                  const SizedBox(height: 16),
                  _buildInteresesSelector(setModalState),
                  const SizedBox(height: 30),
                  Center(child: _buildApplyButton()),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _fetchProfiles() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Obtenemos los IDs a los que ya se les dio like
      final likesSnap = await FirebaseFirestore.instance
          .collection('likes')
          .where('from', isEqualTo: user.uid)
          .get();
      final alreadyLikedIds =
          likesSnap.docs.map((d) => d.data()['to'] as String).toSet();

      final querySnapshot = await FirebaseFirestore.instance
          .collection('usuario')
          .where(FieldPath.documentId, isNotEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> allUsers = querySnapshot.docs
          .where((doc) => !alreadyLikedIds.contains(doc.id))  // ← filtro nuevo
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();

      final interesesSnap =
          await FirebaseFirestore.instance.collection('intereses').get();
      final mapa = <String, String>{};
      for (final doc in interesesSnap.docs) {
        final data = doc.data();
        mapa[doc.id] = data['nombre'] as String? ?? doc.id;
      }

      final filteredList = allUsers.where((u) {
        final edad = u['edad'] is int
            ? u['edad']
            : (int.tryParse(u['edad']?.toString() ?? '0') ?? 0);
        bool cumpleEdad = edad >= _currentFilters.minEdad &&
            edad <= _currentFilters.maxEdad;
        bool cumpleCarrera = _currentFilters.carreras.isEmpty ||
            _currentFilters.carreras.contains(u['carrera']);
        List<String> interesesUsuario =
            List<String>.from(u['intereses'] ?? []);
        bool cumpleIntereses = _currentFilters.intereses.isEmpty ||
            interesesUsuario
                .any((i) => _currentFilters.intereses.contains(i));
        return cumpleEdad && cumpleCarrera && cumpleIntereses;
      }).toList();

      setState(() {
        _catalogoIntereses = mapa;
        _profiles = filteredList;
        _currentIndex = 0;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error cargando perfiles: $e");
      setState(() => _isLoading = false);
    }
  }

  Widget _buildApplyButton() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        _fetchProfiles();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        decoration: BoxDecoration(
          gradient:
              const LinearGradient(colors: [_pinkStart, _orangeEnd]),
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
          'Aplicar Filtros',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        Text(value,
            style: const TextStyle(
                color: _pinkStart,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildCarrerasSelector(StateSetter setModalState) {
    final listaCarreras = [
      'Sistemas',
      'Industrial',
      'Gestión',
      'Mecatrónica',
      'Electrónica'
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: listaCarreras.map((carrera) {
        final isSelected = _currentFilters.carreras.contains(carrera);
        return GestureDetector(
          onTap: () {
            setModalState(() {
              List<String> listaNueva = List.from(_currentFilters.carreras);
              if (isSelected) {
                listaNueva.remove(carrera);
              } else {
                listaNueva.add(carrera);
              }
              _currentFilters.carreras = listaNueva;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? _pinkStart.withOpacity(0.1)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? _pinkStart : Colors.white10,
                width: 1.5,
              ),
            ),
            child: Text(
              carrera,
              style: TextStyle(
                color: isSelected ? Colors.white : _textSecondary,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInteresesSelector(StateSetter setModalState) {
    final listaIntereses = [
      "Deportes",
      "Música",
      "Programación",
      "Cine",
      "Lectura",
      "Viajes",
      "Anime",
      "Videojuegos",
      "Gimnasio"
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: listaIntereses.map((interes) {
        final isSelected = _currentFilters.intereses.contains(interes);
        return FilterChip(
          label: Text(interes),
          selected: isSelected,
          selectedColor: _pinkStart.withOpacity(0.2),
          checkmarkColor: _pinkStart,
          labelStyle: TextStyle(
            color: isSelected ? _pinkStart : _textSecondary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          backgroundColor: Colors.white.withOpacity(0.05),
          shape: StadiumBorder(
            side: BorderSide(
              color: isSelected ? _pinkStart : Colors.white10,
            ),
          ),
          onSelected: (bool selected) {
            setModalState(() {
              if (selected) {
                _currentFilters.intereses = [
                  ..._currentFilters.intereses,
                  interes
                ];
              } else {
                _currentFilters.intereses = _currentFilters.intereses
                    .where((i) => i != interes)
                    .toList();
              }
            });
          },
        );
      }).toList(),
    );
  }

  // ── Modal de búsqueda de perfiles ──────────────────────────────────────────
  void _showSearchModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SearchSheet(catalogoIntereses: _catalogoIntereses),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Match Overlay
// ═══════════════════════════════════════════════════════════════════════════════

class _MatchOverlay extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onClose;
  final VoidCallback onMessage;

  const _MatchOverlay({
    required this.profile,
    required this.onClose,
    required this.onMessage,
  });

  @override
  State<_MatchOverlay> createState() => _MatchOverlayState();
}

class _MatchOverlayState extends State<_MatchOverlay>
    with TickerProviderStateMixin {
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);

  late AnimationController _bgController;
  late AnimationController _contentController;
  late AnimationController _heartController;
  late AnimationController _avatarController;

  late Animation<double> _bgOpacity;
  late Animation<double> _contentScale;
  late Animation<double> _contentOpacity;
  late Animation<double> _heartScale;
  late Animation<double> _heartRotation;
  late Animation<double> _textSlide;
  late Animation<double> _leftAvatarSlide;
  late Animation<double> _rightAvatarSlide;
  late Animation<double> _particleOpacity;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _contentController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _heartController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _avatarController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _bgOpacity =
        CurvedAnimation(parent: _bgController, curve: Curves.easeOut);
    _contentScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.elasticOut),
    );
    _contentOpacity = CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.9), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.1), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 20),
    ]).animate(
        CurvedAnimation(parent: _heartController, curve: Curves.easeOut));
    _heartRotation = Tween<double>(begin: -0.15, end: 0.0).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.elasticOut),
    );
    _textSlide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _leftAvatarSlide = Tween<double>(begin: -80.0, end: 0.0).animate(
      CurvedAnimation(parent: _avatarController, curve: Curves.easeOutBack),
    );
    _rightAvatarSlide = Tween<double>(begin: 80.0, end: 0.0).animate(
      CurvedAnimation(parent: _avatarController, curve: Curves.easeOutBack),
    );
    _particleOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartController);

    _bgController.forward().then((_) {
      _avatarController.forward();
      Future.delayed(const Duration(milliseconds: 100), () {
        _heartController.forward();
        _contentController.forward();
      });
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _contentController.dispose();
    _heartController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  Future<void> _handleClose() async {
    await Future.wait([
      _contentController.reverse(),
      _avatarController.reverse(),
    ]);
    await _bgController.reverse();
    widget.onClose();
  }

  String _nombre(Map<String, dynamic> p) {
    final n = p['nombre'] ?? '';
    final a = p['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Sin nombre' : '$n $a'.trim();
  }

  String? _foto(Map<String, dynamic> p) {
    final f = p['foto_perfil'] as String?;
    return (f != null && f.isNotEmpty) ? f : null;
  }

  @override
  Widget build(BuildContext context) {
    final matchNombre = _nombre(widget.profile);
    final matchFoto = _foto(widget.profile);
    final currentUser = FirebaseAuth.instance.currentUser;

    return FadeTransition(
      opacity: _bgOpacity,
      child: GestureDetector(
        onTap: _handleClose,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1A0A10).withOpacity(0.97),
                const Color(0xFF0D0408).withOpacity(0.97),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _heartController,
                  builder: (_, _) => Transform.scale(
                    scale: _heartScale.value,
                    child: Transform.rotate(
                      angle: _heartRotation.value,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: _particleOpacity.value,
                            child: const _MatchParticles(),
                          ),
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_pinkStart, _orangeEnd],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _pinkStart.withOpacity(0.6 *
                                      _heartScale.value.clamp(0.0, 1.0)),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.favorite_rounded,
                                color: Colors.white, size: 40),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (_, _) => Transform.translate(
                    offset: Offset(0, _textSlide.value),
                    child: Opacity(
                      opacity: _contentOpacity.value,
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (b) => const LinearGradient(
                              colors: [_pinkStart, _orangeEnd],
                            ).createShader(b),
                            child: const Text(
                              '¡Es un Match!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tú y $matchNombre\nse han gustado mutuamente',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 16,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                AnimatedBuilder(
                  animation: _avatarController,
                  builder: (_, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(_leftAvatarSlide.value, 0),
                        child: _MatchAvatar(
                          photoUrl: currentUser?.photoURL,
                          initials: (currentUser?.displayName ?? 'Yo')
                              .substring(0, 1)
                              .toUpperCase(),
                          borderColors: const [_pinkStart, _orangeEnd],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        child: const Icon(Icons.favorite,
                            color: _pinkStart, size: 22),
                      ),
                      Transform.translate(
                        offset: Offset(_rightAvatarSlide.value, 0),
                        child: _MatchAvatar(
                          photoUrl: matchFoto,
                          initials: matchNombre.isNotEmpty
                              ? matchNombre.substring(0, 1).toUpperCase()
                              : '?',
                          borderColors: const [_orangeEnd, _pinkStart],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 44),
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (_, _) => Opacity(
                    opacity: _contentOpacity.value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: widget.onMessage,
                            child: Container(
                              width: double.infinity,
                              height: 54,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [_pinkStart, _orangeEnd]),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: _pinkStart.withOpacity(0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.chat_bubble_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'Enviar mensaje',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          GestureDetector(
                            onTap: _handleClose,
                            child: Container(
                              width: double.infinity,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.15)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.explore_rounded,
                                      color: Colors.white70, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'Seguir explorando',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchAvatar extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  final List<Color> borderColors;

  const _MatchAvatar({
    required this.photoUrl,
    required this.initials,
    required this.borderColors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: borderColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColors.first.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.isNotEmpty
            ? Image.network(photoUrl!, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder())
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF252525),
      child: Center(
        child: Text(initials,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 36,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _MatchParticles extends StatelessWidget {
  const _MatchParticles();

  @override
  Widget build(BuildContext context) {
    const pinkStart = Color(0xFFFF4D6D);
    const orangeEnd = Color(0xFFFF8A00);
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < 8; i++)
            Positioned(
              left: 80 + 65 * _cos(i * 45.0 * 3.14159 / 180) - 6,
              top: 80 + 65 * _sin(i * 45.0 * 3.14159 / 180) - 6,
              child: Container(
                width: i % 2 == 0 ? 10 : 6,
                height: i % 2 == 0 ? 10 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i % 2 == 0 ? pinkStart : orangeEnd,
                ),
              ),
            ),
          for (int i = 0; i < 4; i++)
            Positioned(
              left: 80 +
                  45 * _cos((i * 90.0 + 22.5) * 3.14159 / 180) -
                  4,
              top: 80 +
                  45 * _sin((i * 90.0 + 22.5) * 3.14159 / 180) -
                  4,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.7)),
              ),
            ),
        ],
      ),
    );
  }

  double _cos(double rad) => _cosCalc(rad);
  double _sin(double rad) => _cosCalc(1.5707963 - rad);
  double _cosCalc(double rad) {
    double x = rad % (2 * 3.14159265);
    double result = 1.0;
    double term = 1.0;
    for (int k = 1; k <= 8; k++) {
      term *= -x * x / ((2 * k - 1) * (2 * k));
      result += term;
    }
    return result;
  }
}

class ProfileFilters {
  int minEdad;
  int maxEdad;
  List<String> carreras;
  List<String> intereses;

  ProfileFilters({
    this.minEdad = 18,
    this.maxEdad = 30,
    this.carreras = const [],
    this.intereses = const [],
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bottom sheet de búsqueda de perfiles
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchSheet extends StatefulWidget {
  final Map<String, String> catalogoIntereses;

  const _SearchSheet({required this.catalogoIntereses});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);

  final TextEditingController _searchCtrl = TextEditingController();
  final String _currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('usuario').get();
      if (!mounted) return;
      setState(() {
        _allUsers = snap.docs
            .where((d) => d.id != _currentUserId)
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      _query = q;
      if (q.isEmpty) {
        _results = [];
        return;
      }
      _results = _allUsers.where((u) {
        final nombre = (u['nombre'] ?? '').toString().toLowerCase();
        final apellido = (u['apellido'] ?? '').toString().toLowerCase();
        final carrera = (u['carrera'] ?? '').toString().toLowerCase();
        final nombreCompleto = '$nombre $apellido';
        return nombre.contains(q) ||
            apellido.contains(q) ||
            nombreCompleto.contains(q) ||
            carrera.contains(q);
      }).toList();
    });
  }

  @override
Widget build(BuildContext context) {
  // 1. Definimos la paleta dinámica según el brillo del tema
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Estas variables locales ahora son "punteros" al tema global
    final surface = theme.cardColor; 
    final textPrimary = theme.textTheme.bodyLarge?.color;
    final textSecondary = theme.textTheme.bodyMedium?.color;
    final inputFill = theme.inputDecorationTheme.fillColor;
    final borderColor = theme.inputDecorationTheme.enabledBorder?.borderSide.color ?? Colors.transparent;
    final closeBtnBg = theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}) ?? Colors.white.withOpacity(0.05);

  return DraggableScrollableSheet(
    initialChildSize: 0.9,
    minChildSize: 0.5,
    maxChildSize: 0.95,
    expand: false,
    builder: (context, scrollController) {
      return Container(
        // Aplicamos el color de fondo dinámico al contenedor principal
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // El indicador (handle) superior
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [_pinkStart, _orangeEnd],
                      ).createShader(b),
                      child: const Text(
                        'Buscar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: closeBtnBg, // Color de fondo dinámico
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded,
                            color: textSecondary, size: 18), // Color dinámico
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: inputFill, // Color dinámico
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor), // Borde dinámico
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: TextStyle(
                        color: textPrimary, fontSize: 15), // Color dinámico
                    onChanged: _onQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'Nombre, apellido o carrera...',
                      hintStyle: TextStyle(
                          color: isDark ? const Color(0xFF555555) : const Color(0xFFB0B0B0), 
                          fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: textSecondary, size: 20), // Color dinámico
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded,
                                  color: textSecondary, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onQueryChanged('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _buildResults(scrollController),
              ),
            ],
          ),
        ),
      );
    },
  );
}


  Widget _buildResults(ScrollController scrollController) {

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(_pinkStart),
          strokeWidth: 2,
        ),
      );
    }

    if (_query.isEmpty) {
      return _buildHint(
        icon: Icons.search_rounded,
        title: 'Busca por nombre o carrera',
        sub:
            'Escribe al menos una letra para\nencontrar a alguien en Lince',
      );
    }

    if (_results.isEmpty) {
      return _buildHint(
        icon: Icons.person_search_outlined,
        title: 'Sin resultados',
        sub: 'No encontramos a nadie con "$_query"',
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _buildTile(_results[i]),
    );
  }

  Widget _buildHint(
    
      {required IconData icon,
      required String title,
      required String sub}) {
        final theme = Theme.of(context);
        const _textSecondary = theme.textTheme.bodyMedium?.color ?? Color(0xFFAAAAAA);
        const _textPrimary = theme.textTheme.bodyLarge?.color ?? Colors.white;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _pinkStart.withOpacity(0.12),
                    _orangeEnd.withOpacity(0.08)
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: _pinkStart.withOpacity(0.6), size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(Map<String, dynamic> user) {
    return _SearchResultTile(
      user: user,
      currentUserId: _currentUserId,
      onOpenProfile: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, a, b) =>
                UserProfileScreen(userId: user['id'] as String),
            transitionsBuilder: (_, anim, _, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tile individual de resultado de búsqueda (con botón de like)
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchResultTile extends StatefulWidget {
  final Map<String, dynamic> user;
  final String currentUserId;
  final VoidCallback onOpenProfile;

  const _SearchResultTile({
    required this.user,
    required this.currentUserId,
    required this.onOpenProfile,
  });

  @override
  State<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<_SearchResultTile> {
  static const _card = Color(0xFF252525);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  bool _alreadyLiked = false;
  bool _sendingLike = false;

  @override
  void initState() {
    super.initState();
    _checkLikeStatus();
  }

  Future<void> _checkLikeStatus() async {
    final liked = await hasLiked(
      fromUserId: widget.currentUserId,
      toUserId: widget.user['id'] as String,
    );
    if (mounted && liked) {
      setState(() => _alreadyLiked = true);
    }
  }

  Future<void> _handleLike() async {
    if (_alreadyLiked || _sendingLike) return;
    setState(() => _sendingLike = true);

    final matchId = await sendLikeAndMaybeMatch(
      fromUserId: widget.currentUserId,
      toUserId: widget.user['id'] as String,
    );

    if (!mounted) return;
    setState(() {
      _alreadyLiked = true;
      _sendingLike = false;
    });

    if (matchId != null) {
      _showMatchDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Le diste like a ${_nombreCompleto()} 💖'),
        backgroundColor: _pinkStart,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _showMatchDialog() {
    final nombre = _nombreCompleto();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1A0A10),
                const Color(0xFF0D0408),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _pinkStart.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: _pinkStart.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_pinkStart, _orangeEnd],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: _pinkStart.withOpacity(0.5), blurRadius: 20),
                  ],
                ),
                child:
                    const Icon(Icons.favorite, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [_pinkStart, _orangeEnd],
                ).createShader(b),
                child: const Text(
                  '¡Es un Match!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tú y $nombre se han\ngustado mutuamente',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_pinkStart, _orangeEnd],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'Ver en Matches',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Seguir buscando',
                    style: TextStyle(color: _textSecondary, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nombreCompleto() {
    final n = widget.user['nombre'] ?? '';
    final a = widget.user['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Usuario' : '$n $a'.trim();
  }

  String? _foto() {
    final f = widget.user['foto_perfil'] as String?;
    return (f != null && f.isNotEmpty) ? f : null;
  }

  Widget _placeholder(String nombre) {
    return Container(
      color: const Color(0xFF333333),
      child: Center(
        child: Text(
          nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = _nombreCompleto();
    final foto = _foto();
    final carrera =
        (widget.user['carrera'] as String?)?.trim() ?? '';
    final edad = widget.user['edad']?.toString().trim() ?? '';

    return GestureDetector(
      onTap: widget.onOpenProfile,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_pinkStart, _orangeEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: foto != null
                    ? Image.network(
                        foto,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(nombre),
                      )
                    : _placeholder(nombre),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          nombre,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (edad.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          edad,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (carrera.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.school_outlined,
                            color: _pinkStart, size: 12),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            carrera,
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _alreadyLiked ? null : _handleLike,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: _alreadyLiked
                      ? const LinearGradient(
                          colors: [_pinkStart, _orangeEnd],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: _alreadyLiked
                      ? null
                      : _pinkStart.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _alreadyLiked
                        ? Colors.transparent
                        : _pinkStart.withOpacity(0.3),
                  ),
                  boxShadow: _alreadyLiked
                      ? [
                          BoxShadow(
                            color: _pinkStart.withOpacity(0.4),
                            blurRadius: 10,
                          ),
                        ]
                      : [],
                ),
                child: _sendingLike
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(_pinkStart),
                          ),
                        ),
                      )
                    : Icon(
                        _alreadyLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _alreadyLiked
                            ? Colors.white
                            : _pinkStart,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bottom sheet de likes recibidos
// ═══════════════════════════════════════════════════════════════════════════════

class _LikesReceivedSheet extends StatelessWidget {
  final String currentUserId;

  const _LikesReceivedSheet({required this.currentUserId});

  static const _surface = Color(0xFF1E1E1E);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _pinkStart.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        color: _pinkStart, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (b) => const LinearGradient(
                            colors: [_pinkStart, _orangeEnd],
                          ).createShader(b),
                          child: const Text(
                            'Te dieron like',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Personas interesadas en ti',
                          style:
                              TextStyle(color: _textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: _textSecondary, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('likes')
                    .where('to', isEqualTo: currentUserId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(_pinkStart),
                        strokeWidth: 2,
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState();
                  }

                  final docs = [...snapshot.data!.docs];
                  docs.sort((a, b) {
                    final ta = (a.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                    final tb = (b.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                    if (ta == null && tb == null) return 0;
                    if (ta == null) return 1;
                    if (tb == null) return -1;
                    return tb.compareTo(ta);
                  });

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final fromId = data['from'] as String? ?? '';
                      final ts = data['timestamp'] as Timestamp?;
                      return _LikeReceivedTile(
                        fromUserId: fromId,
                        currentUserId: currentUserId,
                        timestamp: ts,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _pinkStart.withOpacity(0.12),
                    _orangeEnd.withOpacity(0.08)
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.favorite_border_rounded,
                  color: _pinkStart.withOpacity(0.5), size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sin likes aún',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando alguien te dé like,\nlo verás aquí primero.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tile de un like recibido
// ═══════════════════════════════════════════════════════════════════════════════

class _LikeReceivedTile extends StatefulWidget {
  final String fromUserId;
  final String currentUserId;
  final Timestamp? timestamp;

  const _LikeReceivedTile({
    required this.fromUserId,
    required this.currentUserId,
    required this.timestamp,
  });

  @override
  State<_LikeReceivedTile> createState() => _LikeReceivedTileState();
}

class _LikeReceivedTileState extends State<_LikeReceivedTile> {
  static const _card = Color(0xFF252525);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _alreadyLikedBack = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _checkLikeBack();
  }

  Future<void> _loadUser() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuario')
          .doc(widget.fromUserId)
          .get();
      if (!mounted) return;
      setState(() {
        _user = doc.exists ? doc.data() : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkLikeBack() async {
    final liked = await hasLiked(
      fromUserId: widget.currentUserId,
      toUserId: widget.fromUserId,
    );
    if (mounted) {
      setState(() => _alreadyLikedBack = liked);
    }
  }

  Future<void> _handleLikeBack() async {
    if (_alreadyLikedBack || _sending) return;
    setState(() => _sending = true);

    final matchId = await sendLikeAndMaybeMatch(
      fromUserId: widget.currentUserId,
      toUserId: widget.fromUserId,
    );

    if (!mounted) return;
    setState(() {
      _alreadyLikedBack = true;
      _sending = false;
    });

    if (matchId != null) {
      _showMatchDialog();
    }
  }

  void _showMatchDialog() {
    final nombre = _nombreCompleto();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1A0A10),
                const Color(0xFF0D0408),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _pinkStart.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: _pinkStart.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_pinkStart, _orangeEnd],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: _pinkStart.withOpacity(0.5), blurRadius: 20),
                  ],
                ),
                child:
                    const Icon(Icons.favorite, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [_pinkStart, _orangeEnd],
                ).createShader(b),
                child: const Text(
                  '¡Es un Match!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tú y $nombre se han\ngustado mutuamente',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_pinkStart, _orangeEnd],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'Ver en Matches',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, b) =>
            UserProfileScreen(userId: widget.fromUserId),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
              parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _nombreCompleto() {
    if (_user == null) return 'Usuario';
    final n = _user!['nombre'] ?? '';
    final a = _user!['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Usuario' : '$n $a'.trim();
  }

  String? _foto() {
    if (_user == null) return null;
    final f = _user!['foto_perfil'] as String?;
    return (f != null && f.isNotEmpty) ? f : null;
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final dt = ts.toDate().toLocal();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 72,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(_pinkStart),
            ),
          ),
        ),
      );
    }

    if (_user == null) return const SizedBox.shrink();

    final nombre = _nombreCompleto();
    final foto = _foto();
    final edad = _user!['edad']?.toString().trim() ?? '';
    final carrera = (_user!['carrera'] as String?)?.trim() ?? '';

    return GestureDetector(
      onTap: _openProfile,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_pinkStart, _orangeEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: foto != null
                    ? Image.network(
                        foto,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(nombre),
                      )
                    : _placeholder(nombre),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          nombre,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (edad.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          edad,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (carrera.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            carrera,
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('·',
                            style: TextStyle(
                                color: _textSecondary, fontSize: 12)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _formatTime(widget.timestamp),
                        style: const TextStyle(
                          color: _pinkStart,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _alreadyLikedBack ? null : _handleLikeBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: _alreadyLikedBack
                      ? const LinearGradient(
                          colors: [_pinkStart, _orangeEnd],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: _alreadyLikedBack
                      ? null
                      : _pinkStart.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _alreadyLikedBack
                        ? Colors.transparent
                        : _pinkStart.withOpacity(0.3),
                  ),
                  boxShadow: _alreadyLikedBack
                      ? [
                          BoxShadow(
                              color: _pinkStart.withOpacity(0.4),
                              blurRadius: 10),
                        ]
                      : [],
                ),
                child: _sending
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(_pinkStart),
                          ),
                        ),
                      )
                    : Icon(
                        _alreadyLikedBack
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _alreadyLikedBack
                            ? Colors.white
                            : _pinkStart,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(String nombre) {
    return Container(
      color: const Color(0xFF333333),
      child: Center(
        child: Text(
          nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/*
// 1. Definimos la paleta dinámica según el brillo del tema
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Estas variables locales ahora son "punteros" al tema global
    final surface = theme.cardColor; 
    final textPrimary = theme.textTheme.bodyLarge?.color;
    final textSecondary = theme.textTheme.bodyMedium?.color;
    final inputFill = theme.inputDecorationTheme.fillColor;
    final borderColor = theme.inputDecorationTheme.enabledBorder?.borderSide.color ?? Colors.transparent;
    final closeBtnBg = theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}) ?? Colors.white.withOpacity(0.05);
*/