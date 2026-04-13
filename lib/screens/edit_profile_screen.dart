import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nombreController;
  late TextEditingController _apellidoController;
  late TextEditingController _bioController;
  late TextEditingController _carreraController;

  File? _imageFile;
  bool _isSaving = false;
  String? _currentImageUrl;

  // ── Paleta ─────────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);
  static const _inputFill = Color(0xFF252525);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFFAAAAAA);

  @override
  void initState() {
    super.initState();
    _nombreController =
        TextEditingController(text: widget.userData['nombre']);
    _apellidoController =
        TextEditingController(text: widget.userData['apellido']);
    _bioController =
        TextEditingController(text: widget.userData['biografia']);
    _carreraController =
        TextEditingController(text: widget.userData['carrera']);
    _currentImageUrl = widget.userData['foto_perfil'];
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _bioController.dispose();
    _carreraController.dispose();
    super.dispose();
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
        final ref = FirebaseStorage.instance
            .ref()
            .child('perfiles/${user.uid}.jpg');
        await ref.putFile(_imageFile!);
        finalUrl = await ref.getDownloadURL();
      }
      await FirebaseFirestore.instance
          .collection('usuario')
          .doc(user.uid)
          .update({
        'nombre': _nombreController.text.trim(),
        'apellido': _apellidoController.text.trim(),
        'biografia': _bioController.text.trim(),
        'carrera': _carreraController.text.trim(),
        'foto_perfil': finalUrl,
        'ultima_actualizacion': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
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
                _buildImageEdit(),
                const SizedBox(height: 32),
                _buildTextField(
                    'Nombre', _nombreController, Icons.person_outline_rounded),
                _buildTextField('Apellido', _apellidoController,
                    Icons.person_outline_rounded),
                _buildTextField(
                    'Carrera', _carreraController, Icons.school_outlined),
                _buildTextField(
                    'Biografía', _bioController, Icons.article_outlined,
                    maxLines: 3),
              ],
            ),
          ),
          if (_isSaving) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'EDITAR PERFIL',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      centerTitle: true,
      actions: [
        if (!_isSaving)
          GestureDetector(
            onTap: _saveChanges,
            child: Container(
              margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_pinkStart, _orangeEnd]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Text(
                  'Guardar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageEdit() {
    return Center(
      child: Stack(
        children: [
          // ── Avatar con borde gradiente ─────────────────────────────────
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
          // ── Botón cámara ───────────────────────────────────────────────
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_pinkStart, _orangeEnd]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8)
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