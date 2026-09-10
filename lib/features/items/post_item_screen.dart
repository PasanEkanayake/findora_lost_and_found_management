import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/location/current_location.dart';
import '../../core/ml/category_mapper.dart';
import '../../core/ml/tflite_classifier.dart';
import '../../core/ml/tflite_provider.dart';
import '../matches/data/matches_providers.dart';
import 'data/items_providers.dart';

/// Reporting form. Photos are classified on-device twice, deliberately:
/// once eagerly after the first photo (purely to suggest a category while
/// the user is still filling out the rest of the form), and once more for
/// every photo right before submit (to get the exact embedding that gets
/// stored). The eager pass is a minor duplicate of work for that one
/// photo — an easy optimization later is to cache and reuse its result.
class PostItemScreen extends ConsumerStatefulWidget {
  const PostItemScreen({super.key});

  @override
  ConsumerState<PostItemScreen> createState() => _PostItemScreenState();
}

class _PostItemScreenState extends ConsumerState<PostItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();

  String _type = 'lost';
  String? _categoryId;
  final List<File> _photos = [];

  bool _isSuggesting = false;
  String? _detectedLabel;
  double? _detectedConfidence;

  bool _isLocating = false;
  double? _latitude;
  double? _longitude;
  String? _locationLabel;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
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

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final file = File(picked.path);
    final isFirstPhoto = _photos.isEmpty;
    setState(() => _photos.add(file));
    if (isFirstPhoto) _suggestCategoryFromPhoto(file);
  }

  /// Runs the on-device model on the first photo purely for a live
  /// "Detected: X" suggestion — never blocks the form, and fails silently
  /// (logged via debugPrint) if the model asset isn't in place yet.
  Future<void> _suggestCategoryFromPhoto(File file) async {
    setState(() => _isSuggesting = true);
    try {
      final classifier = await ref.read(tfliteClassifierProvider.future);
      final result = await classifier.classify(file);
      if (!mounted) return;
      setState(() {
        _detectedLabel = result.label;
        _detectedConfidence = result.confidence;
      });

      if (_categoryId == null) {
        final suggestedName = mapImagenetLabelToCategory(result.label);
        final categories = await ref.read(categoriesProvider.future);
        for (final category in categories) {
          if (category.name == suggestedName) {
            if (mounted) setState(() => _categoryId = category.id);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Category suggestion skipped (model not ready?): $e');
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      final position = await getCurrentPositionOrNull();
      if (position == null) {
        _showMessage(
          'Could not get your location. Check permissions and try again.',
          isError: true,
        );
        return;
      }

      String label = 'Pinned location';
      try {
        // geocoding 5.x replaced the old top-level placemarkFromCoordinates()
        // function with an instance method on the Geocoding class.
        final placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          label = [p.street, p.locality]
              .where((part) => part != null && part.isNotEmpty)
              .join(', ');
          if (label.isEmpty) label = 'Pinned location';
        }
      } catch (_) {
        // Reverse geocoding can fail independently of getting a fix — the
        // coordinates are still useful even without a friendly label.
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationLabel = label;
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Classifies every kept photo right before upload — run here rather
  /// than eagerly per-pick so photos the user removes never get wasted
  /// inference time, and so it's a single obvious place to look if
  /// embeddings ever come back wrong.
  Future<List<ClassificationResult?>> _classifyAllPhotos() async {
    TfliteClassifier classifier;
    try {
      classifier = await ref.read(tfliteClassifierProvider.future);
    } catch (e) {
      debugPrint('On-device model unavailable, posting without AI matching: $e');
      return List<ClassificationResult?>.filled(_photos.length, null);
    }

    final results = <ClassificationResult?>[];
    for (final photo in _photos) {
      try {
        results.add(await classifier.classify(photo));
      } catch (e) {
        debugPrint('Classification failed for a photo: $e');
        results.add(null);
      }
    }
    return results;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photos.isEmpty) {
      _showMessage('Add at least one photo.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final classifications = await _classifyAllPhotos();

      await ref.read(itemsRepositoryProvider).createItem(
            type: _type,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            categoryId: _categoryId,
            photos: _photos,
            classifications: classifications,
            latitude: _latitude,
            longitude: _longitude,
            locationLabel: _locationLabel,
          );

      if (!mounted) return;
      ref.invalidate(itemsFeedProvider);
      // The record_matches_for_image trigger runs synchronously as part of
      // the item_images insert above, so any matches already exist by now.
      ref.invalidate(matchesProvider);
      context.pop();
    } catch (_) {
      _showMessage(
        'Could not post this item. Check your connection and try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report an item'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'lost', label: Text('I lost this')),
                  ButtonSegment(value: 'found', label: Text('I found this')),
                ],
                selected: {_type},
                onSelectionChanged: (value) => setState(() => _type = value.first),
              ),
              const SizedBox(height: 20),
              _PhotoRow(
                photos: _photos,
                onAdd: _showPhotoSourceSheet,
                onRemove: (i) => setState(() => _photos.removeAt(i)),
              ),
              if (_isSuggesting || _detectedLabel != null) ...[
                const SizedBox(height: 10),
                _DetectionBadge(
                  isLoading: _isSuggesting,
                  label: _detectedLabel,
                  confidence: _detectedConfidence,
                ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Give it a short title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              categoriesAsync.when(
                loading: () => const InputDecorator(
                  decoration: InputDecoration(labelText: 'Category'),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, __) => InputDecorator(
                  decoration: const InputDecoration(labelText: 'Category'),
                  child: Text(
                    "Couldn't load categories",
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                data: (categories) => DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isLocating ? null : _detectLocation,
                icon: _isLocating
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.location_on_outlined),
                label: Text(_locationLabel ?? 'Add current location'),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _isSubmitting ? null : _handleSubmit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Post'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectionBadge extends StatelessWidget {
  const _DetectionBadge({required this.isLoading, this.label, this.confidence});

  final bool isLoading;
  final String? label;
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (isLoading)
            const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLoading
                  ? 'Analyzing photo…'
                  : 'Detected: ${_prettify(label!)}'
                      '${confidence != null ? ' (${(confidence! * 100).round()}%)' : ''}'
                      ' — category pre-filled below, change it if needed.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _prettify(String rawLabel) {
    return rawLabel.replaceAll('_', ' ');
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<File> photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      photos[i],
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.5),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
              child: Icon(Icons.add_a_photo_outlined, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
