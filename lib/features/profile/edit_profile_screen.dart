import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/auth_providers.dart';
import 'data/profile_providers.dart';

/// Lets the user change their display name, phone, and avatar. Reads its
/// initial values from [myProfileProvider] and writes back through
/// [ProfileRepository], invalidating that same provider on success so
/// ProfileScreen picks up the change immediately.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _picker = ImagePicker();

  bool _initialized = false;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  File? _pendingAvatar;
  String? _existingAvatarUrl;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? theme.colorScheme.error : null,
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _pendingAvatar = file;
      _isUploadingAvatar = true;
    });
    try {
      final url = await ref.read(profileRepositoryProvider).uploadAvatar(file);
      setState(() => _existingAvatarUrl = url);
      ref.invalidate(myProfileProvider);
    } catch (_) {
      _showMessage("Couldn't upload that photo. Try again.", isError: true);
      setState(() => _pendingAvatar = null);
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            fullName: _nameController.text.trim(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
          );
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      _showMessage('Profile updated.');
      context.pop();
    } catch (_) {
      _showMessage("Couldn't save your changes. Try again.", isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(myProfileProvider);
    final email = ref.watch(currentUserProvider)?.email;

    // Pre-fill the form fields exactly once, when the profile first loads
    // — not on every rebuild, or the user's in-progress edits would keep
    // getting overwritten by the fetched value.
    profileAsync.whenData((profile) {
      if (!_initialized) {
        _nameController.text = profile.fullName ?? '';
        _phoneController.text = profile.phone ?? '';
        _existingAvatarUrl = profile.avatarUrl;
        _initialized = true;
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load your profile.")),
        data: (profile) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage: _pendingAvatar != null
                            ? FileImage(_pendingAvatar!) as ImageProvider
                            : (_existingAvatarUrl != null
                                ? CachedNetworkImageProvider(_existingAvatarUrl!)
                                : null),
                        child: (_pendingAvatar == null && _existingAvatarUrl == null)
                            ? Icon(Icons.person_outline,
                                size: 48, color: theme.colorScheme.onPrimaryContainer)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: _isUploadingAvatar ? null : _pickAvatar,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primary,
                            child: _isUploadingAvatar
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : Icon(Icons.camera_alt_outlined,
                                    size: 18, color: theme.colorScheme.onPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                // Email isn't editable here — changing it means
                // re-verifying a new address with Supabase Auth, which is
                // a separate flow from editing profile fields.
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  child: Text(email ?? '—'),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _isSaving ? null : _handleSave,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
