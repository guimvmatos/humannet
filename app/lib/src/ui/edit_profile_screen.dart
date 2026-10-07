import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'error_messages.dart';

/// Edita nome de exibição e bio. Retorna `true` via Navigator se salvou.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  final _hometown = TextEditingController();
  final _city = TextEditingController();
  final _school = TextEditingController();

  /// Só envia cidade/escola depois de carregar os valores atuais (para não
  /// apagar sem querer).
  bool _placesLoaded = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = widget.session.user;
    _name = TextEditingController(text: user?.displayName ?? '');
    _bio = TextEditingController(text: user?.bio ?? '');
    unawaited(_loadPlaces());
  }

  Future<void> _loadPlaces() async {
    final token = widget.session.token;
    final username = widget.session.user?.username;
    if (token == null || username == null) return;
    try {
      final p = await widget.session.api.profile(token, username);
      if (!mounted) return;
      setState(() {
        _hometown.text = p.hometown;
        _city.text = p.city;
        _school.text = p.school;
        _placesLoaded = true;
      });
    } catch (_) {
      // Sem os valores atuais, os campos ficam desativados.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _hometown.dispose();
    _city.dispose();
    _school.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.session.api.updateProfile(
        token,
        displayName: _name.text.trim(),
        bio: _bio.text.trim(),
        hometown: _placesLoaded ? _hometown.text.trim() : null,
        city: _placesLoaded ? _city.text.trim() : null,
        school: _placesLoaded ? _school.text.trim() : null,
      );
      widget.session.updateUser(user);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar perfil'),
        actions: [
          TextButton(
            key: const Key('save_profile_button'),
            onPressed: _busy ? null : _save,
            child: const Text('Salvar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            key: const Key('display_name_field'),
            controller: _name,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Nome de exibição',
              helperText: 'Opcional. Deixe vazio para mostrar só o @usuário.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('bio_field'),
            controller: _bio,
            maxLength: 300,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(labelText: 'Bio'),
          ),
          const SizedBox(height: 16),
          Text(
            'Para reencontrar pessoas (opcional)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            'Aparece no seu perfil e ajuda a sugerir amigos: quem é da mesma '
            'cidade ou estudou no mesmo lugar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextField(
            key: const Key('hometown_field'),
            controller: _hometown,
            enabled: _placesLoaded,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Cidade natal'),
          ),
          TextField(
            key: const Key('city_field'),
            controller: _city,
            enabled: _placesLoaded,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Cidade onde mora'),
          ),
          TextField(
            key: const Key('school_field'),
            controller: _school,
            enabled: _placesLoaded,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Escola ou faculdade',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
