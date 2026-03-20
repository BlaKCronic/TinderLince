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
  
  // 1. Inputs cargados con info actual
  late TextEditingController _nombreController;
  late TextEditingController _apellidoController;
  late TextEditingController _bioController;
  late TextEditingController _carreraController;

  File? _imageFile;
  bool _isSaving = false;
  String? _currentImageUrl;

  static const _bgDark = Color(0xFF0A1F0A);
  static const _greenGlow = Color(0xFF6DCC6D);
  static const _greenAccent = Color(0xFF4CAF50);
  static const _cardBg = Color(0xFF152415);

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.userData['nombre']);
    _apellidoController = TextEditingController(text: widget.userData['apellido']);
    _bioController = TextEditingController(text: widget.userData['biografia']);
    _carreraController = TextEditingController(text: widget.userData['carrera']);
    _currentImageUrl = widget.userData['foto_perfil'];
  }

  // Selección de imagen 
  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  // Lógica de Guardado 
  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return; // Validación (Checklist #7)

    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String? finalImageUrl = _currentImageUrl;

      // Subida a Storage si hay imagen nueva 
      if (_imageFile != null) {
        final ref = FirebaseStorage.instance.ref().child('perfiles/${user.uid}.jpg');
        await ref.putFile(_imageFile!);
        finalImageUrl = await ref.getDownloadURL();
      }

      // Actualización en Firestore 
      await FirebaseFirestore.instance.collection('usuario').doc(user.uid).update({
        'nombre': _nombreController.text.trim(),
        'apellido': _apellidoController.text.trim(),
        'biografia': _bioController.text.trim(),
        'carrera': _carreraController.text.trim(),
        'foto_perfil': finalImageUrl,
        'ultima_actualizacion': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.pop(context, true); // Retornar éxito
    } catch (e) {
      // Mensaje de error 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de conexión: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('EDITAR PERFIL', style: TextStyle(letterSpacing: 2, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context), // Cancelar 
        ),
        actions: [
          if (!_isSaving)
            TextButton(
              onPressed: _saveChanges,
              child: const Text('GUARDAR', style: TextStyle(color: _greenGlow, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildImageEdit(),
                const SizedBox(height: 30),
                _buildTextField('Nombre', _nombreController, Icons.person_outline),
                _buildTextField('Apellido', _apellidoController, Icons.person_outline),
                _buildTextField('Carrera', _carreraController, Icons.school_outlined),
                _buildTextField('Biografía', _bioController, Icons.article_outlined, maxLines: 3),
              ],
            ),
          ),
          if (_isSaving) _buildLoadingOverlay() // Indicador progreso 
        ],
      ),
    );
  }

  Widget _buildImageEdit() {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _greenGlow, width: 2),
              boxShadow: [BoxShadow(color: _greenGlow.withOpacity(0.2), blurRadius: 20)],
            ),
            child: ClipOval(
              child: _imageFile != null
                  ? Image.file(_imageFile!, fit: BoxFit.cover)
                  : (_currentImageUrl != null 
                      ? Image.network(_currentImageUrl!, fit: BoxFit.cover)
                      : const Icon(Icons.person, size: 80, color: Colors.white24)),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                backgroundColor: _greenAccent,
                radius: 20,
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _greenGlow, fontSize: 12),
          prefixIcon: Icon(icon, color: _greenGlow, size: 20),
          filled: true,
          fillColor: _cardBg,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _greenGlow)),
        ),
        validator: (value) => value!.isEmpty ? 'Este campo es obligatorio' : null,
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_greenGlow)),
            SizedBox(height: 20),
            Text('Actualizando perfil...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}