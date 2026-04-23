import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chat_screen.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen>
    with SingleTickerProviderStateMixin {
  // ── Paleta ─────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  final String _currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? '';

  // Cache de datos de usuario para evitar múltiples lecturas
  final Map<String, Map<String, dynamic>> _usersCache = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Expanded(child: _buildMatchesList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [_pinkStart, _orangeEnd],
            ).createShader(b),
            child: const Text(
              'Matches',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tus conexiones',
            style: TextStyle(color: _textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // NOTA: Usamos el stream SIN orderBy y ordenamos del lado cliente.
  // Esto evita requerir un índice compuesto en Firestore y funciona tanto
  // para matches recientes (que tienen solo `timestamp`) como para los que
  // ya tienen `lastMessageTime` tras el primer mensaje.
  Widget _buildMatchesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('matches')
          .where('users', arrayContains: _currentUserId)
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

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error cargando matches:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textSecondary, fontSize: 13),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        // Ordenamos client-side: lastMessageTime > timestamp de creación
        final docs = [...snapshot.data!.docs];
        docs.sort((a, b) {
          final da = a.data() as Map<String, dynamic>;
          final db = b.data() as Map<String, dynamic>;
          final ta = (da['lastMessageTime'] ?? da['timestamp']) as Timestamp?;
          final tb = (db['lastMessageTime'] ?? db['timestamp']) as Timestamp?;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta); // descendente (más reciente primero)
        });

        return _buildList(docs);
      },
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> docs) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final matchData = docs[index].data() as Map<String, dynamic>;
        final matchId = docs[index].id;
        final List<dynamic> users = matchData['users'] ?? [];
        final otherUserId = users.firstWhere(
          (u) => u != _currentUserId,
          orElse: () => '',
        ) as String;

        if (otherUserId.isEmpty) return const SizedBox.shrink();

        return _MatchTile(
          matchId: matchId,
          otherUserId: otherUserId,
          matchData: matchData,
          currentUserId: _currentUserId,
          usersCache: _usersCache,
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
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
                  color: _pinkStart.withOpacity(0.5), size: 44),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sin matches aún',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Cuando alguien te dé like de vuelta,\naparecerá aquí para que puedan chatear.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_pinkStart, _orangeEnd],
                ),
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
                '❤ Sigue explorando',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tile individual de un match ────────────────────────────────────────────────
class _MatchTile extends StatefulWidget {
  final String matchId;
  final String otherUserId;
  final Map<String, dynamic> matchData;
  final String currentUserId;
  final Map<String, Map<String, dynamic>> usersCache;

  const _MatchTile({
    required this.matchId,
    required this.otherUserId,
    required this.matchData,
    required this.currentUserId,
    required this.usersCache,
  });

  @override
  State<_MatchTile> createState() => _MatchTileState();
}

class _MatchTileState extends State<_MatchTile> {
  static const _surface = Color(0xFF1E1E1E);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  Map<String, dynamic>? _otherUser;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    if (widget.usersCache.containsKey(widget.otherUserId)) {
      setState(() {
        _otherUser = widget.usersCache[widget.otherUserId];
        _loading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuario')
          .doc(widget.otherUserId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        widget.usersCache[widget.otherUserId] = data;
        setState(() {
          _otherUser = data;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _nombre(Map<String, dynamic> u) {
    final n = u['nombre'] ?? '';
    final a = u['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Usuario' : '$n $a'.trim();
  }

  String? _foto(Map<String, dynamic> u) {
    final f = u['foto_perfil'] as String?;
    return (f != null && f.isNotEmpty) ? f : null;
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final dt = ts.toDate().toLocal();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Ayer';
    } else if (diff.inDays < 7) {
      const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  }

  bool get _hasUnread {
    final lastSeen =
        widget.matchData['lastSeen_${widget.currentUserId}'] as Timestamp?;
    final lastMsgTime =
        widget.matchData['lastMessageTime'] as Timestamp?;
    final lastSender =
        widget.matchData['lastMessageSender'] as String?;

    if (lastMsgTime == null) return false;
    if (lastSender == widget.currentUserId) return false;
    if (lastSeen == null) return true;
    return lastMsgTime.compareTo(lastSeen) > 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 76,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
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

    if (_otherUser == null) return const SizedBox.shrink();

    final nombre = _nombre(_otherUser!);
    final foto = _foto(_otherUser!);

    // Si no hay lastMessage, mostramos un CTA amistoso.
    final raw = widget.matchData['lastMessage'] as String?;
    final lastMessage = (raw == null || raw.isEmpty) ? 'Di hola 👋' : raw;

    // Preferimos lastMessageTime; si no existe, usamos timestamp de creación
    final ts = (widget.matchData['lastMessageTime'] ??
        widget.matchData['timestamp']) as Timestamp?;
    final lastTime = _formatTime(ts);

    final unread = _hasUnread;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, a, b) => ChatScreen(
              matchId: widget.matchId,
              otherUserId: widget.otherUserId,
              otherUserName: nombre,
              otherUserPhoto: foto,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                SlideTransition(
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
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: unread ? _pinkStart.withOpacity(0.06) : _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: unread
                ? _pinkStart.withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Row(
          children: [
            // Avatar con gradiente
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
                boxShadow: [
                  BoxShadow(
                    color: _pinkStart.withOpacity(unread ? 0.4 : 0.2),
                    blurRadius: unread ? 12 : 6,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: foto != null
                    ? Image.network(
                        foto,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(nombre),
                      )
                    : _placeholder(nombre),
              ),
            ),
            const SizedBox(width: 14),
            // Texto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight:
                          unread ? FontWeight.w700 : FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lastMessage,
                    style: TextStyle(
                      color: unread ? Colors.white70 : _textSecondary,
                      fontSize: 13,
                      fontWeight: unread
                          ? FontWeight.w500
                          : FontWeight.w400,
                      fontStyle: raw == null || raw.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Tiempo + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lastTime,
                  style: TextStyle(
                    color: unread ? _pinkStart : _textSecondary,
                    fontSize: 11,
                    fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (unread) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_pinkStart, _orangeEnd],
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
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