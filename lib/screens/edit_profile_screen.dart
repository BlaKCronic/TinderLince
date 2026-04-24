import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';

import 'main_nav_screen.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final bool isNewUser;

  const EditProfileScreen({
    super.key,
    required this.userData,
    this.isNewUser = false,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _Interes {
  final String id;
  final String nombre;
  final String categoria;
  _Interes({required this.id, required this.nombre, required this.categoria});
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nombreController;
  late TextEditingController _apellidoController;
  late TextEditingController _bioController;
  late TextEditingController _carreraController;
  late TextEditingController _edadController;

  File? _imageFile;
  bool _isSaving = false;
  bool _loadingIntereses = true;
  String? _currentImageUrl;
  String? _generoSeleccionado;

  List<_Interes> _catalogoIntereses = [];
  Set<String> _interesesSeleccionados = {};

  // ── Paleta ─────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);
  static const _inputFill = Color(0xFF252525);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  static const _generos = [
    {'valor': 'hombre', 'label': 'Hombre', 'emoji': '👨'},
    {'valor': 'mujer', 'label': 'Mujer', 'emoji': '👩'},
    {'valor': 'no_binario', 'label': 'No binario', 'emoji': '🧑'},
    {'valor': 'prefiero_no_decir', 'label': 'No especificar', 'emoji': '🤐'},
  ];

  @override
  void initState() {
    super.initState();
    _nombreController =
        TextEditingController(text: widget.userData['nombre'] ?? '');
    _apellidoController =
        TextEditingController(text: widget.userData['apellido'] ?? '');
    _bioController =
        TextEditingController(text: widget.userData['biografia'] ?? '');
    _carreraController =
        TextEditingController(text: widget.userData['carrera'] ?? '');
    _edadController =
        TextEditingController(text: widget.userData['edad']?.toString() ?? '');
    _currentImageUrl = widget.userData['foto_perfil'];

    // Género — puede ser String o List (legacy)
    final generoRaw = widget.userData['genero'];
    if (generoRaw is String && generoRaw.isNotEmpty) {
      _generoSeleccionado = generoRaw;
    } else if (generoRaw is List && generoRaw.isNotEmpty) {
      _generoSeleccionado = generoRaw.first.toString();
    }

    final interesesActuales =
        List<String>.from(widget.userData['intereses'] ?? []);
    _interesesSeleccionados = interesesActuales.toSet();

    _fetchCatalogoIntereses();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _bioController.dispose();
    _carreraController.dispose();
    _edadController.dispose();
    super.dispose();
  }

  Future<void> _fetchCatalogoIntereses() async {
    try {
      // Sin orderBy para evitar requerir índice compuesto en Firestore
      final snap = await FirebaseFirestore.instance
          .collection('intereses')
          .get();
      final lista = snap.docs.map((doc) {
        final data = doc.data();
        return _Interes(
          id: doc.id,
          nombre: data['nombre'] as String? ?? doc.id,
          categoria: data['categoria'] as String? ?? 'General',
        );
      }).toList();

      // Ordenamos client-side por categoría y luego por nombre
      lista.sort((a, b) {
        final cat = a.categoria.compareTo(b.categoria);
        return cat != 0 ? cat : a.nombre.compareTo(b.nombre);
      });

      if (mounted) {
        setState(() {
          _catalogoIntereses = lista;
          _loadingIntereses = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingIntereses = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String? finalUrl = _currentImageUrl;

      if (_imageFile != null) {
        final cloudinary = CloudinaryPublic(
          'dl8rz3aqk',
          'perfiles_preset',
          cache: false,
        );
        CloudinaryResponse response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(
            _imageFile!.path,
            resourceType: CloudinaryResourceType.Image,
          ),
        );
        finalUrl = response.secureUrl;
      }

      final edadStr = _edadController.text.trim();
      final edadInt = edadStr.isNotEmpty ? int.tryParse(edadStr) : null;

      await FirebaseFirestore.instance
          .collection('usuario')
          .doc(user.uid)
          .update({
        'nombre': _nombreController.text.trim(),
        'apellido': _apellidoController.text.trim(),
        'biografia': _bioController.text.trim(),
        'carrera': _carreraController.text.trim(),
        'edad': edadInt ?? edadStr,
        'genero': _generoSeleccionado ?? '',
        'foto_perfil': finalUrl,
        'intereses': _interesesSeleccionados.toList(),
        'ultima_actualizacion': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      if (widget.isNewUser) {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, a, b) => const MainNavScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
          (route) => false,
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: _pinkStart,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Map<String, List<_Interes>> get _interesesPorCategoria {
    final Map<String, List<_Interes>> mapa = {};
    for (final interes in _catalogoIntereses) {
      mapa.putIfAbsent(interes.categoria, () => []).add(interes);
    }
    return mapa;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                if (widget.isNewUser) _buildWelcomeBanner(),
                _buildImageEdit(),
                const SizedBox(height: 32),
                _buildTextField(
                    'Nombre', _nombreController, Icons.person_outline_rounded),
                _buildTextField('Apellido', _apellidoController,
                    Icons.person_outline_rounded),
                _buildTextField(
                    'Carrera', _carreraController, Icons.school_outlined),
                // ── Edad ──────────────────────────────────────────────────
                _buildEdadField(),
                // ── Género ────────────────────────────────────────────────
                _buildGeneroSection(),
                const SizedBox(height: 18),
                _buildTextField(
                    'Biografía', _bioController, Icons.article_outlined,
                    maxLines: 3),
                const SizedBox(height: 8),
                _buildInteresesSection(),
                const SizedBox(height: 16),
                _buildSaveButton(),
              ],
            ),
          ),
          if (_isSaving) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: widget.isNewUser
          ? null
          : IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
      title: Text(
        widget.isNewUser ? 'COMPLETA TU PERFIL' : 'EDITAR PERFIL',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      centerTitle: true,
    );
  }

  // ── Banner de bienvenida ───────────────────────────────────────────────────
  Widget _buildWelcomeBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_pinkStart.withOpacity(0.15), _orangeEnd.withOpacity(0.10)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _pinkStart.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Text('👋', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¡Bienvenido a Lince!',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
                SizedBox(height: 2),
                Text(
                  'Cuéntanos un poco sobre ti para encontrar tu mejor match.',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar ─────────────────────────────────────────────────────────────────
  Widget _buildImageEdit() {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_pinkStart, _orangeEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _pinkStart.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: _imageFile != null
                  ? Image.file(_imageFile!, fit: BoxFit.cover)
                  : (_currentImageUrl != null && _currentImageUrl!.isNotEmpty
                      ? Image.network(_currentImageUrl!, fit: BoxFit.cover)
                      : Container(
                          color: _inputFill,
                          child: const Icon(Icons.person_rounded,
                              size: 60, color: Color(0xFF444444)),
                        )),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(colors: [_pinkStart, _orangeEnd]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.3), blurRadius: 8)
                  ],
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Campo de texto genérico ────────────────────────────────────────────────
  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: _textPrimary, fontSize: 15),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: _textSecondary, size: 20),
              filled: true,
              fillColor: _inputFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF2E2E2E))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _pinkStart, width: 1.5)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _pinkStart)),
              focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _pinkStart, width: 1.5)),
              errorStyle: const TextStyle(color: _pinkStart, fontSize: 12),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Campo obligatorio' : null,
          ),
        ],
      ),
    );
  }

  // ── Campo edad ─────────────────────────────────────────────────────────────
  Widget _buildEdadField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Edad',
              style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _edadController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            style: const TextStyle(color: _textPrimary, fontSize: 15),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.cake_outlined,
                  color: _textSecondary, size: 20),
              hintText: 'Ej. 21',
              hintStyle:
                  const TextStyle(color: Color(0xFF555555), fontSize: 15),
              filled: true,
              fillColor: _inputFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF2E2E2E))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _pinkStart, width: 1.5)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _pinkStart)),
              focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _pinkStart, width: 1.5)),
              errorStyle: const TextStyle(color: _pinkStart, fontSize: 12),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obligatorio';
              final age = int.tryParse(v);
              if (age == null || age < 18 || age > 99) {
                return 'Ingresa una edad válida (18-99)';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ── Selector de género ─────────────────────────────────────────────────────
  Widget _buildGeneroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [_pinkStart, _orangeEnd],
              ).createShader(b),
              child: const Text(
                'GÉNERO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
            ),
            if (_generoSeleccionado == null) ...[
              const SizedBox(width: 8),
              const Text('*',
                  style: TextStyle(color: _pinkStart, fontSize: 14)),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _generos.map((g) {
            final seleccionado = _generoSeleccionado == g['valor'];
            return GestureDetector(
              onTap: () =>
                  setState(() => _generoSeleccionado = g['valor'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: seleccionado
                      ? const LinearGradient(
                          colors: [_pinkStart, _orangeEnd])
                      : null,
                  color: seleccionado ? null : _inputFill,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: seleccionado
                        ? Colors.transparent
                        : const Color(0xFF3A3A3A),
                  ),
                  boxShadow: seleccionado
                      ? [
                          BoxShadow(
                            color: _pinkStart.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(g['emoji']!,
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      g['label']!,
                      style: TextStyle(
                        color:
                            seleccionado ? Colors.white : _textSecondary,
                        fontSize: 13,
                        fontWeight: seleccionado
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (seleccionado) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 14),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Sección de intereses ───────────────────────────────────────────────────
  Widget _buildInteresesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [_pinkStart, _orangeEnd],
              ).createShader(b),
              child: const Text(
                'INTERESES',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_interesesSeleccionados.length} seleccionados)',
              style: const TextStyle(color: _textSecondary, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Selecciona tus hobbies y gustos para encontrar personas afines.',
          style: TextStyle(color: _textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_loadingIntereses)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_pinkStart),
                strokeWidth: 2,
              ),
            ),
          )
        else if (_catalogoIntereses.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'No hay intereses disponibles por el momento.',
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
          )
        else
          ..._interesesPorCategoria.entries.map(
            (entry) => _buildCategoriaChips(entry.key, entry.value),
          ),
      ],
    );
  }

  Widget _buildCategoriaChips(String categoria, List<_Interes> intereses) {
    final iconos = <String, IconData>{
      'Deportes': Icons.sports_soccer_rounded,
      'Entretenimiento': Icons.movie_outlined,
      'Social': Icons.people_outline_rounded,
      'Arte': Icons.palette_outlined,
      'Tecnología': Icons.computer_outlined,
      'Música': Icons.music_note_outlined,
      'Gastronomía': Icons.restaurant_outlined,
      'Naturaleza': Icons.eco_outlined,
      'Viajes': Icons.flight_outlined,
      'General': Icons.star_outline_rounded,
    };
    final icono = iconos[categoria] ?? Icons.tag_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: _pinkStart, size: 16),
              const SizedBox(width: 6),
              Text(
                categoria,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: intereses.map((interes) {
              final seleccionado =
                  _interesesSeleccionados.contains(interes.id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (seleccionado) {
                      _interesesSeleccionados.remove(interes.id);
                    } else {
                      _interesesSeleccionados.add(interes.id);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: seleccionado
                        ? const LinearGradient(
                            colors: [_pinkStart, _orangeEnd])
                        : null,
                    color: seleccionado ? null : _inputFill,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: seleccionado
                          ? Colors.transparent
                          : const Color(0xFF3A3A3A),
                    ),
                    boxShadow: seleccionado
                        ? [
                            BoxShadow(
                              color: _pinkStart.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (seleccionado) ...[
                        const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        interes.nombre,
                        style: TextStyle(
                          color: seleccionado
                              ? Colors.white
                              : _textSecondary,
                          fontSize: 13,
                          fontWeight: seleccionado
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Botón guardar ──────────────────────────────────────────────────────────
  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [_pinkStart, _orangeEnd]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
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
          onTap: _isSaving ? null : _saveChanges,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Text(
              widget.isNewUser ? 'Comenzar →' : 'Guardar cambios',
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

  // ── Overlay de carga ───────────────────────────────────────────────────────
  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_pinkStart),
              ),
              SizedBox(height: 18),
              Text('Guardando cambios...',
                  style: TextStyle(color: _textSecondary, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}