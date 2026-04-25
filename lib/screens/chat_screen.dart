import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'user_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final String matchId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhoto;

  const ChatScreen({
    super.key,
    required this.matchId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhoto,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  // ── Paleta ─────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);
  static const _inputFill = Color(0xFF252525);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _matchGreen = Color(0xFF4CAF50);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isSending = false;

  final String _currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? '';

  // Colección de mensajes: mensajes/{matchId}/chats
  CollectionReference get _messagesRef => FirebaseFirestore.instance
      .collection('mensajes')
      .doc(widget.matchId)
      .collection('chats');

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
    // NOTA: antes había listeners que llamaban setState en cada tecla, lo que
    // repintaba toda la pantalla (incluyendo la lista de mensajes). Ahora el
    // botón de enviar y el borde del input se reconstruyen localmente con
    // ListenableBuilder, sin tocar el resto de la UI.
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await FirebaseFirestore.instance
          .collection('matches')
          .doc(widget.matchId)
          .set({
        'lastSeen_$_currentUserId': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();

    try {
      final batch = FirebaseFirestore.instance.batch();

      final msgRef = _messagesRef.doc();
      batch.set(msgRef, {
        'texto': text,
        'senderId': _currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
        'leido': false,
      });

      final matchRef = FirebaseFirestore.instance
          .collection('matches')
          .doc(widget.matchId);
      batch.set(
        matchRef,
        {
          'lastMessage': text,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageSender': _currentUserId,
        },
        SetOptions(merge: true),
      );

      // FIX: ordenamos `users` alfabéticamente para que el campo sea
      // idéntico sin importar quién envía el mensaje. Antes se guardaba
      // [yo, otro] y eso sobrescribía el orden cada vez, quedando
      // inconsistente entre escrituras de distintos usuarios.
      final msgDocRef = FirebaseFirestore.instance
          .collection('mensajes')
          .doc(widget.matchId);
      final sortedUsers = [_currentUserId, widget.otherUserId]..sort();
      batch.set(
          msgDocRef,
          {
            'mensaje': text,
            'users': sortedUsers,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      await batch.commit();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 100,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al enviar: $e'),
          backgroundColor: _pinkStart,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MENÚ DE OPCIONES (tres puntos)
  // ══════════════════════════════════════════════════════════════════════════

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _optionTile(
                  icon: Icons.person_outline_rounded,
                  label: 'Ver perfil',
                  subtitle: 'Ver el perfil completo',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openUserProfile();
                  },
                ),
                _optionTile(
                  icon: Icons.info_outline_rounded,
                  label: 'Ver detalles',
                  subtitle: 'Edad, carrera, intereses',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showUserDetails();
                  },
                ),
                _optionTile(
                  icon: Icons.flag_outlined,
                  label: 'Reportar',
                  subtitle: 'Informar contenido inapropiado',
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showReportDialog();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? _pinkStart : _textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDestructive
                    ? _pinkStart.withOpacity(0.12)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: _textSecondary.withOpacity(0.5), size: 20),
          ],
        ),
      ),
    );
  }

  // ── Ver perfil completo ────────────────────────────────────────────────────
  void _openUserProfile() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, b) =>
            UserProfileScreen(userId: widget.otherUserId),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // ── Bottom sheet con detalles ──────────────────────────────────────────────
  void _showUserDetails() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _UserDetailsSheet(
        userId: widget.otherUserId,
        onOpenProfile: () {
          Navigator.pop(ctx);
          _openUserProfile();
        },
      ),
    );
  }

  // ── Diálogo de reporte ─────────────────────────────────────────────────────
  void _showReportDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ReportSheet(
        reportadoUserId: widget.otherUserId,
        reportadoNombre: widget.otherUserName,
        matchId: widget.matchId,
        currentUserId: _currentUserId,
        onReported: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                'Reporte enviado. Gracias por ayudar a mantener la comunidad segura.'),
            backgroundColor: _matchGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ));
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessagesList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        // Tap sobre el avatar/nombre también abre el perfil
        onTap: _openUserProfile,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
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
                child: widget.otherUserPhoto != null &&
                        widget.otherUserPhoto!.isNotEmpty
                    ? Image.network(
                        widget.otherUserPhoto!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarPlaceholder(),
                      )
                    : _avatarPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUserName,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [_pinkStart, _orangeEnd],
                    ).createShader(b),
                    child: const Text(
                      '❤ Match',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: _textSecondary),
          onPressed: _showOptionsMenu,
          tooltip: 'Opciones',
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: Colors.white.withOpacity(0.07),
        ),
      ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      color: const Color(0xFF333333),
      child: Center(
        child: Text(
          widget.otherUserName.isNotEmpty
              ? widget.otherUserName[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _messagesRef
          .orderBy('timestamp', descending: false)
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
          return _buildEmptyChat();
        }

        final docs = snapshot.data!.docs;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final isMe = data['senderId'] == _currentUserId;
            final isFirst = index == 0 ||
                (docs[index - 1].data()
                        as Map<String, dynamic>)['senderId'] !=
                    data['senderId'];
            final isLast = index == docs.length - 1 ||
                (docs[index + 1].data()
                        as Map<String, dynamic>)['senderId'] !=
                    data['senderId'];

            return _MessageBubble(
              text: data['texto'] as String? ?? '',
              isMe: isMe,
              timestamp: data['timestamp'] as Timestamp?,
              isFirst: isFirst,
              isLast: isLast,
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _pinkStart.withOpacity(0.15),
                    _orangeEnd.withOpacity(0.1)
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: _pinkStart, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              '¡Haz match con ${widget.otherUserName}!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sé el primero en enviar un mensaje\ny comenzar la conversación.',
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

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Campo de texto ───────────────────────────────────────────
          // Solo el borde se repinta cuando cambia el foco, no la pantalla entera.
          Expanded(
            child: ListenableBuilder(
              listenable: _focusNode,
              builder: (context, _) {
                return Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: _inputFill,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? _pinkStart.withOpacity(0.5)
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 15,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Escribe un mensaje...',
                            hintStyle: TextStyle(
                              color: Color(0xFF555555),
                              fontSize: 15,
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 12),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          // ── Botón enviar ─────────────────────────────────────────────
          // Solo este botón se repinta en cada tecla, no la lista de mensajes.
          ListenableBuilder(
            listenable: _textController,
            builder: (context, _) {
              final hasText = _textController.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText && !_isSending ? _sendMessage : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: hasText
                        ? const LinearGradient(
                            colors: [_pinkStart, _orangeEnd],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: hasText ? null : const Color(0xFF2A2A2A),
                    shape: BoxShape.circle,
                    boxShadow: hasText
                        ? [
                            BoxShadow(
                              color: _pinkStart.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : [],
                  ),
                  child: _isSending
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: hasText
                              ? Colors.white
                              : const Color(0xFF555555),
                          size: 20,
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET: Detalles del usuario
// ═════════════════════════════════════════════════════════════════════════════

class _UserDetailsSheet extends StatefulWidget {
  final String userId;
  final VoidCallback onOpenProfile;

  const _UserDetailsSheet({
    required this.userId,
    required this.onOpenProfile,
  });

  @override
  State<_UserDetailsSheet> createState() => _UserDetailsSheetState();
}

class _UserDetailsSheetState extends State<_UserDetailsSheet> {
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _card = Color(0xFF252525);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  Map<String, dynamic>? _userData;
  Map<String, String> _catalogoIntereses = {};
  bool _loading = true;

  static const _generoLabels = {
    'hombre': '👨 Hombre',
    'mujer': '👩 Mujer',
    'no_binario': '🧑 No binario',
    'prefiero_no_decir': '🤐 No especificado',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('usuario')
            .doc(widget.userId)
            .get(),
        FirebaseFirestore.instance.collection('intereses').get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot;
      final interesesSnap = results[1] as QuerySnapshot;

      final mapa = <String, String>{};
      for (final doc in interesesSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        mapa[doc.id] = data['nombre'] as String? ?? doc.id;
      }

      if (!mounted) return;
      setState(() {
        _userData = userDoc.exists
            ? userDoc.data() as Map<String, dynamic>
            : null;
        _catalogoIntereses = mapa;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _nombreCompleto(Map<String, dynamic> u) {
    final n = u['nombre'] ?? '';
    final a = u['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Usuario' : '$n $a'.trim();
  }

  String? _foto(Map<String, dynamic> u) {
    final f = u['foto_perfil'] as String?;
    return (f != null && f.isNotEmpty) ? f : null;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        if (_loading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_pinkStart),
                strokeWidth: 2,
              ),
            ),
          );
        }

        if (_userData == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                'No se pudo cargar la información',
                style: TextStyle(color: _textSecondary),
              ),
            ),
          );
        }

        final nombre = _nombreCompleto(_userData!);
        final foto = _foto(_userData!);
        final edad = _userData!['edad']?.toString().trim() ?? '';
        final carrera =
            (_userData!['carrera'] as String?)?.trim() ?? '';
        final bio =
            (_userData!['biografia'] as String?)?.trim() ?? '';
        final generoRaw = _userData!['genero'];
        final generoKey = generoRaw is String
            ? generoRaw
            : (generoRaw is List && generoRaw.isNotEmpty
                ? generoRaw.first.toString()
                : '');
        final generoLabel = _generoLabels[generoKey] ?? '';

        final interesIds = List<String>.from(_userData!['intereses'] ?? []);
        final interesNombres = interesIds
            .map((id) => _catalogoIntereses[id] ?? id)
            .toList();

        return ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Avatar + Nombre
            Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_pinkStart, _orangeEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _pinkStart.withOpacity(0.35),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: foto != null
                        ? Image.network(
                            foto,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _nameFallback(nombre),
                          )
                        : _nameFallback(nombre),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          colors: [_pinkStart, _orangeEnd],
                        ).createShader(b),
                        child: const Text(
                          'DETALLES',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Datos básicos
            if (edad.isNotEmpty)
              _detailRow(
                icon: Icons.cake_outlined,
                label: 'Edad',
                value: '$edad años',
              ),
            if (generoLabel.isNotEmpty)
              _detailRow(
                icon: Icons.person_outline_rounded,
                label: 'Género',
                value: generoLabel,
              ),
            if (carrera.isNotEmpty)
              _detailRow(
                icon: Icons.school_outlined,
                label: 'Carrera',
                value: carrera,
              ),

            const SizedBox(height: 8),

            // Biografía
            if (bio.isNotEmpty) ...[
              _sectionTitle('Biografía', Icons.article_outlined),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Text(
                  bio,
                  style: const TextStyle(
                    color: Color(0xFFDDDDDD),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Intereses
            if (interesNombres.isNotEmpty) ...[
              _sectionTitle('Intereses', Icons.favorite_border_rounded),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: interesNombres
                    .map((i) => _interesChip(i))
                    .toList(),
              ),
              const SizedBox(height: 24),
            ] else ...[
              const SizedBox(height: 12),
            ],

            // Botón ir al perfil
            _gradientButton(
              label: 'Ver perfil completo',
              icon: Icons.arrow_forward_rounded,
              onTap: widget.onOpenProfile,
            ),
          ],
        );
      },
    );
  }

  Widget _nameFallback(String nombre) {
    return Container(
      color: _card,
      child: Center(
        child: Text(
          nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _pinkStart.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _pinkStart, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: _pinkStart, size: 16),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _interesChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _pinkStart.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pinkStart.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _pinkStart,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient:
              const LinearGradient(colors: [_pinkStart, _orangeEnd]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _pinkStart.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET: Reportar usuario
// ═════════════════════════════════════════════════════════════════════════════

class _ReportSheet extends StatefulWidget {
  final String reportadoUserId;
  final String reportadoNombre;
  final String matchId;
  final String currentUserId;
  final VoidCallback onReported;

  const _ReportSheet({
    required this.reportadoUserId,
    required this.reportadoNombre,
    required this.matchId,
    required this.currentUserId,
    required this.onReported,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _card = Color(0xFF252525);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  static const _motivos = [
    {'key': 'contenido_inapropiado', 'label': 'Contenido inapropiado', 'icon': Icons.block_rounded},
    {'key': 'acoso', 'label': 'Acoso o amenazas', 'icon': Icons.warning_amber_rounded},
    {'key': 'spam', 'label': 'Spam o publicidad', 'icon': Icons.campaign_outlined},
    {'key': 'perfil_falso', 'label': 'Perfil falso', 'icon': Icons.person_off_outlined},
    {'key': 'menor_edad', 'label': 'Menor de edad', 'icon': Icons.shield_outlined},
    {'key': 'otro', 'label': 'Otro motivo', 'icon': Icons.more_horiz_rounded},
  ];

  String? _motivoSeleccionado;
  final TextEditingController _descripcionCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviarReporte() async {
    if (_motivoSeleccionado == null || _enviando) return;
    setState(() => _enviando = true);

    try {
      // Buscamos la etiqueta legible del motivo seleccionado
      final motivoLabel = _motivos.firstWhere(
        (m) => m['key'] == _motivoSeleccionado,
        orElse: () => {'label': _motivoSeleccionado!},
      )['label'] as String;

      await FirebaseFirestore.instance.collection('reportes').add({
        'reportador_id': widget.currentUserId,
        'reportado_id': widget.reportadoUserId,
        'matchId': widget.matchId,
        'motivo': motivoLabel,
        'descripcion': _descripcionCtrl.text.trim(),
        'fecha': FieldValue.serverTimestamp(),
        'estado': 'pendiente',
      });

      if (!mounted) return;
      Navigator.pop(context);
      widget.onReported();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al enviar reporte: $e'),
        backgroundColor: _pinkStart,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _pinkStart.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.flag_rounded,
                      color: _pinkStart, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reportar usuario',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Estás reportando a ${widget.reportadoNombre}',
                        style: const TextStyle(
                            color: _textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            const Text(
              'Motivo del reporte',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),

            // Lista de motivos
            ..._motivos.map((m) {
              final key = m['key'] as String;
              final selected = _motivoSeleccionado == key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _motivoSeleccionado = key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? _pinkStart.withOpacity(0.1)
                          : _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? _pinkStart
                            : Colors.white.withOpacity(0.06),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          m['icon'] as IconData,
                          color: selected ? _pinkStart : _textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            m['label'] as String,
                            style: TextStyle(
                              color: selected
                                  ? _textPrimary
                                  : const Color(0xFFDDDDDD),
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check_circle_rounded,
                              color: _pinkStart, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 14),

            const Text(
              'Descripción (opcional)',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _descripcionCtrl,
              maxLines: 3,
              maxLength: 300,
              style: const TextStyle(
                  color: _textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Cuéntanos más detalles...',
                hintStyle:
                    const TextStyle(color: Color(0xFF555555), fontSize: 14),
                filled: true,
                fillColor: _card,
                counterStyle: const TextStyle(color: _textSecondary),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.06)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _pinkStart, width: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Botones
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _enviando
                        ? null
                        : () => Navigator.pop(context),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancelar',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: (_motivoSeleccionado == null || _enviando)
                        ? null
                        : _enviarReporte,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: _motivoSeleccionado == null
                            ? null
                            : const LinearGradient(
                                colors: [_pinkStart, _orangeEnd]),
                        color: _motivoSeleccionado == null
                            ? const Color(0xFF2A2A2A)
                            : null,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _motivoSeleccionado == null
                            ? []
                            : [
                                BoxShadow(
                                  color: _pinkStart.withOpacity(0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                      ),
                      child: Center(
                        child: _enviando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(
                                      Colors.white),
                                ),
                              )
                            : Text(
                                'Enviar reporte',
                                style: TextStyle(
                                  color: _motivoSeleccionado == null
                                      ? const Color(0xFF555555)
                                      : Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Burbuja de mensaje
// ═════════════════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final Timestamp? timestamp;
  final bool isFirst;
  final bool isLast;

  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.timestamp,
    required this.isFirst,
    required this.isLast,
  });

  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _surface = Color(0xFF252525);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMe ? 20 : (isFirst ? 20 : 4)),
      topRight: Radius.circular(isMe ? (isFirst ? 20 : 4) : 20),
      bottomLeft: Radius.circular(isMe ? 20 : (isLast ? 20 : 4)),
      bottomRight: Radius.circular(isMe ? (isLast ? 4 : 4) : 20),
    );

    return Padding(
      padding: EdgeInsets.only(
        top: isFirst ? 8 : 2,
        bottom: isLast ? 4 : 2,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) const SizedBox(width: 4),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: isMe
                  ? BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_pinkStart, _orangeEnd],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: radius,
                      boxShadow: [
                        BoxShadow(
                          color: _pinkStart.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    )
                  : BoxDecoration(
                      color: _surface,
                      borderRadius: radius,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.06)),
                    ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(timestamp),
                    style: TextStyle(
                      color: isMe
                          ? Colors.white.withOpacity(0.6)
                          : _textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }
}