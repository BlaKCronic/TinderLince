import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Vista de perfil de solo lectura para ver el perfil de otra persona
/// (desde el chat o desde los detalles del match).
class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _userData;
  Map<String, String> _catalogoIntereses = {};
  bool _isLoading = true;
  String? _errorMessage;

  static const _generoLabels = {
    'hombre': '👨 Hombre',
    'mujer': '👩 Mujer',
    'no_binario': '🧑 No binario',
    'prefiero_no_decir': '🤐 No especificado',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('usuario')
            .doc(widget.userId)
            .get(),
        FirebaseFirestore.instance.collection('intereses').get(),
      ]);

      if (!mounted) return;

      final userDoc = results[0] as DocumentSnapshot;
      final interesesSnap = results[1] as QuerySnapshot;

      final mapa = <String, String>{};
      for (final doc in interesesSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        mapa[doc.id] = data['nombre'] as String? ?? doc.id;
      }

      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data() as Map<String, dynamic>;
          _catalogoIntereses = mapa;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Perfil no encontrado.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar el perfil.';
      });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String get _nombreCompleto {
    final n = _userData?['nombre'] ?? '';
    final a = _userData?['apellido'] ?? '';
    return '$n $a'.trim().isEmpty ? 'Usuario' : '$n $a'.trim();
  }

  String get _carrera => (_userData?['carrera'] as String?)?.trim() ?? '';

  String get _bio {
    final b = (_userData?['biografia'] as String?)?.trim() ?? '';
    return b.isEmpty ? 'Sin biografía' : b;
  }

  String? get _fotoPerfil => _userData?['foto_perfil'];
  List<String> get _fotos => List<String>.from(_userData?['fotos'] ?? []);

  List<String> get _interesesNombres {
    final ids = List<String>.from(_userData?['intereses'] ?? []);
    return ids.map((id) => _catalogoIntereses[id] ?? id).toList();
  }

  String get _edadDisplay {
    final e = _userData?['edad'];
    if (e == null) return '';
    final str = e.toString().trim();
    return str.isEmpty ? '' : '$str años';
  }

  String get _generoDisplay {
    final g = _userData?['genero'];
    if (g == null) return '';
    final str = g is String
        ? g
        : (g is List && g.isNotEmpty ? g.first.toString() : '');
    return _generoLabels[str] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? _buildLoading()
          : _errorMessage != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: Theme.of(context).colorScheme.primary, size: 56),
                    const SizedBox(height: 16),
                    Text(_errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return CustomScrollView(
      slivers: [
        _buildSliverAppBar(),
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 12),
              _buildInfoChips(),
              const SizedBox(height: 12),
              _buildBioCard(),
              const SizedBox(height: 12),
              if (_interesesNombres.isNotEmpty) _buildIntereses(),
              const SizedBox(height: 12),
              _buildTabBar(),
              _buildTabContent(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _buildHeader(),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.15), Theme.of(context).scaffoldBackgroundColor],
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
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            if (_carrera.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _carrera,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
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
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
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
                        color: Theme.of(context).cardColor,
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => _defaultAvatar(),
              )
            : _defaultAvatar(),
      ),
    );
  }

  Widget _defaultAvatar() {
    return Container(
      color: Theme.of(context).cardColor,
      child: const Icon(Icons.person_rounded,
          color: Color(0xFF444444), size: 52),
    );
  }

  Widget _buildInfoChips() {
    final chips = <Widget>[];

    if (_edadDisplay.isNotEmpty) {
      chips.add(_infoChip(Icons.cake_outlined, _edadDisplay));
    }
    if (_generoDisplay.isNotEmpty) {
      chips.add(_infoChip(null, _generoDisplay));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: chips
            .expand((c) => [c, const SizedBox(width: 10)])
            .toList()
          ..removeLast(),
      ),
    );
  }

  Widget _infoChip(IconData? icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 14),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildBioCard() {
    final bioEmpty = _bio == 'Sin biografía';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (b) => LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
              ).createShader(b),
              child: Text(
                'BIOGRAFÍA',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
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
                color: bioEmpty
                    ? Theme.of(context).textTheme.bodyMedium?.color
                    : const Color(0xFFDDDDDD),
                fontSize: 14,
                height: 1.6,
                fontStyle: bioEmpty ? FontStyle.italic : FontStyle.normal,
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
        itemCount: _interesesNombres.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            _interesesNombres[i],
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600),
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
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.3),
          tabs: const [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.grid_view_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('FOTOS'),
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
      builder: (_, _) => _tabController.index == 0
          ? _buildFotosGrid()
          : _buildEmptyTab(
              icon: Icons.videocam_outlined,
              message: 'Sin reels',
              sub: 'Esta persona aún no ha compartido reels',
            ),
    );
  }

  Widget _buildFotosGrid() {
    if (_fotos.isEmpty) {
      return _buildEmptyTab(
        icon: Icons.photo_library_outlined,
        message: 'Sin fotos',
        sub: 'Esta persona aún no ha agregado más fotos',
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: Theme.of(context).cardColor,
            child: const Icon(Icons.broken_image_outlined,
                color: Color(0xFF444444), size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTab(
      {required IconData icon,
      required String message,
      required String sub}) {
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
}