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

        // Solo necesitamos los matchIds (IDs de los documentos), ordenados
        // por lastMessageTime / timestamp. Cada tile leerá los datos de su
        // propio match por sí mismo. Esto evita CUALQUIER posibilidad de
        // que un tile reciba datos del match equivocado.
        final docs = [...snapshot.data!.docs];
        docs.sort((a, b) {
          final da = a.data() as Map<String, dynamic>;
          final db = b.data() as Map<String, dynamic>;
          final ta = (da['lastMessageTime'] ?? da['timestamp']) as Timestamp?;
          final tb = (db['lastMessageTime'] ?? db['timestamp']) as Timestamp?;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });

        final matchIds = docs.map((d) => d.id).toList();

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: matchIds.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final matchId = matchIds[index];
            // Cada tile es independiente: tiene su propio key y su propio
            // stream amarrado al matchId. Imposible que se "rote" la info
            // entre tiles al reordenar la lista.
            return _MatchTile(
              key: ValueKey(matchId),
              matchId: matchId,
              currentUserId: _currentUserId,
            );
          },
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

// ═════════════════════════════════════════════════════════════════════════════
// Tile individual de un match — completamente autónomo
//
// Cada tile lee:
//   - matches/{matchId}    → para lastMessage, lastMessageTime, etc.
//   - usuario/{otherUid}   → para nombre y foto del otro usuario
//
// No recibe matchData ni usersCache por parámetro. Esto garantiza que
// jamás puede mostrar datos de otro match.
// ═════════════════════════════════════════════════════════════════════════════
class _MatchTile extends StatelessWidget {
  final String matchId;
  final String currentUserId;

  const _MatchTile({
    super.key,
    required this.matchId,
    required this.currentUserId,
  });

  static const _surface = Color(0xFF1E1E1E);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  /// Calcula el otro UID a partir del matchId (formato `uidA_uidB` con
  /// uidA < uidB alfabéticamente). No depende del campo `users` del doc.
  String _resolveOtherUserId() {
    final parts = matchId.split('_');
    if (parts.length != 2) return '';
    if (parts[0] == currentUserId) return parts[1];
    if (parts[1] == currentUserId) return parts[0];
    return '';
  }

  String _nombre(Map<String, dynamic>? u) {
    if (u == null) return 'Usuario';
    final n = u['nombre'] ?? '';
    final a = u['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Usuario' : '$n $a'.trim();
  }

  String? _foto(Map<String, dynamic>? u) {
    if (u == null) return null;
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

  bool _hasUnread(Map<String, dynamic> matchData) {
    final lastSeen =
        matchData['lastSeen_$currentUserId'] as Timestamp?;
    final lastMsgTime = matchData['lastMessageTime'] as Timestamp?;
    final lastSender = matchData['lastMessageSender'] as String?;

    if (lastMsgTime == null) return false;
    if (lastSender == currentUserId) return false;
    if (lastSeen == null) return true;
    return lastMsgTime.compareTo(lastSeen) > 0;
  }

  @override
  Widget build(BuildContext context) {
    final otherUserId = _resolveOtherUserId();
    if (otherUserId.isEmpty) return const SizedBox.shrink();

    // Stream del match (lastMessage, timestamps, etc.)
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('matches')
          .doc(matchId)
          .snapshots(),
      builder: (context, matchSnap) {
        final matchData = matchSnap.hasData && matchSnap.data!.exists
            ? matchSnap.data!.data() as Map<String, dynamic>
            : <String, dynamic>{};

        // Stream del usuario (nombre y foto)
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('usuario')
              .doc(otherUserId)
              .snapshots(),
          builder: (context, userSnap) {
            if (!userSnap.hasData) {
              return _loadingTile();
            }

            final userData = userSnap.data!.exists
                ? userSnap.data!.data() as Map<String, dynamic>
                : null;

            return _buildTileContent(
              context: context,
              matchData: matchData,
              userData: userData,
              otherUserId: otherUserId,
            );
          },
        );
      },
    );
  }

  Widget _loadingTile() {
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

  Widget _buildTileContent({
    required BuildContext context,
    required Map<String, dynamic> matchData,
    required Map<String, dynamic>? userData,
    required String otherUserId,
  }) {
    final nombre = _nombre(userData);
    final foto = _foto(userData);

    final raw = matchData['lastMessage'] as String?;
    final lastMessage =
        (raw == null || raw.isEmpty) ? 'Di hola 👋' : raw;

    final ts = (matchData['lastMessageTime'] ??
        matchData['timestamp']) as Timestamp?;
    final lastTime = _formatTime(ts);

    final unread = _hasUnread(matchData);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, a, b) => ChatScreen(
              key: ValueKey('chat_$matchId'),
              matchId: matchId,
              otherUserId: otherUserId,
              otherUserName: nombre,
              otherUserPhoto: foto,
            ),
            transitionsBuilder: (_, anim, __, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOutCubic)),
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
                      fontWeight:
                          unread ? FontWeight.w500 : FontWeight.w400,
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
                    fontWeight:
                        unread ? FontWeight.w600 : FontWeight.w400,
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