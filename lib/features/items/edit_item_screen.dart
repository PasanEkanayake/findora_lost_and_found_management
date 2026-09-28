import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/location/location_picker_screen.dart';
import '../../core/ml/tflite_classifier.dart';
import '../../core/ml/tflite_provider.dart';
import '../matches/data/matches_providers.dart';
import 'data/item_model.dart';
import 'data/items_providers.dart';
import 'widgets/photo_strip.dart';

/// Editing an existing item — title, description, category, location, event
/// time and **photos** (add, remove, or replace). Not the lost-vs-found
/// type; see ItemsRepository.updateItem's doc for why.
///
/// Photo changes are held locally until Save: nothing is uploaded or
/// deleted while you're still tapping around, and backing out discards them.
class EditItemScreen extends ConsumerStatefulWidget {
  const EditItemScreen({super.key, required this.item});

  final ItemModel item;

  @override
  ConsumerState<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends ConsumerState<EditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  String? _categoryId;
  double? _latitude;
  double? _longitude;
  String? _locationLabel;
  DateTime? _eventTime;
  bool _isSaving = false;
  bool _coordsLoaded = false;

  final _picker = ImagePicker();

  /// What the strip shows: photos already saved on the server (remote), in
  /// the order they were added, followed by any picked this session (local).
  List<PhotoStripItem> _photos = [];

  /// Saved photos the person removed (or replaced) — only actually deleted
  /// on Save.
  final List<({String id, String url})> _removedImages = [];

  bool _photosLoading = true;
  bool _photosLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _titleController = TextEditingController(text: widget.item.title);
    _descriptionController = TextEditingController(text: widget.item.description ?? '');
    _categoryId = widget.item.categoryId;
    _locationLabel = widget.item.locationLabel;
    _eventTime = widget.item.eventTime;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Fetches the item's saved photos. Deliberately doesn't call setState
  /// before its first await (initState calls this, where that would be an
  /// error) — [_retryLoadPhotos] flips the loading flags for a manual retry.
  Future<void> _loadPhotos() async {
    try {
      final images = await ref.read(itemsRepositoryProvider).fetchItemImages(widget.item.id);
      if (!mounted) return;
      setState(() {
        _photos = [
          for (final image in images) PhotoStripItem.remote(imageId: image.id, url: image.url),
        ];
        _removedImages.clear();
        _photosLoadFailed = false;
      });
    } catch (e) {
      debugPrint('Could not load this item\'s photos: $e');
      if (mounted) setState(() => _photosLoadFailed = true);
    } finally {
      if (mounted) setState(() => _photosLoading = false);
    }
  }

  void _retryLoadPhotos() {
    setState(() {
      _photosLoading = true;
      _photosLoadFailed = false;
    });
    _loadPhotos();
  }

  Future<void> _addPhoto() async {
    final file = await pickPhotoWithSheet(context, _picker);
    if (file == null || !mounted) return;
    setState(() => _photos.add(PhotoStripItem.local(file)));
  }

  void _removePhotoAt(int index) {
    setState(() {
      final removed = _photos.removeAt(index);
      if (removed.isRemote) {
        _removedImages.add((id: removed.imageId!, url: removed.url!));
      }
    });
  }

  /// Replacing = removing the old photo and adding the new one, so the new
  /// photo joins the end of the row — which is also where it will sit once
  /// saved (photos are ordered by when they were added).
  Future<void> _replacePhoto(int index) async {
    final file = await pickPhotoWithSheet(context, _picker);
    if (file == null || !mounted || index >= _photos.length) return;
    setState(() {
      final old = _photos.removeAt(index);
      if (old.isRemote) {
        _removedImages.add((id: old.imageId!, url: old.url!));
      }
      _photos.add(PhotoStripItem.local(file));
    });
  }

  /// Same idea as PostItemScreen's classification step: an embedding per
  /// new photo, or `null` for any the on-device model couldn't handle.
  Future<List<ClassificationResult?>> _classify(List<File> files) async {
    TfliteClassifier classifier;
    try {
      classifier = await ref.read(tfliteClassifierProvider.future);
    } catch (e) {
      debugPrint('On-device model unavailable, saving photos without AI matching: $e');
      return List<ClassificationResult?>.filled(files.length, null);
    }

    final results = <ClassificationResult?>[];
    for (final file in files) {
      try {
        results.add(await classifier.classify(file));
      } catch (e) {
        debugPrint('Classification failed for a photo: $e');
        results.add(null);
      }
    }
    return results;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// The item's existing lat/lng come from a separate RPC (see
  /// itemCoordinatesProvider's doc — a geography column doesn't
  /// serialize predictably over a plain select), so they arrive a beat
  /// after the rest of the form. Cheap to just prime local state once
  /// they land rather than re-fetching every rebuild.
  void _primeCoordsOnce(({double latitude, double longitude})? coords) {
    if (_coordsLoaded || coords == null) return;
    _coordsLoaded = true;
    _latitude = coords.latitude;
    _longitude = coords.longitude;
  }

  Future<void> _adjustLocationOnMap() async {
    final startLat = _latitude ?? 0.0;
    final startLng = _longitude ?? 0.0;

    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) =>
            LocationPickerScreen(initialLatitude: startLat, initialLongitude: startLng),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;
      _locationLabel = picked.label;
    });
  }

  Future<void> _pickEventTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _eventTime ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eventTime ?? now),
    );
    if (!mounted) return;

    setState(() {
      _eventTime = time == null
          ? DateTime(date.year, date.month, date.day)
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final repo = ref.read(itemsRepositoryProvider);

    // 1) The details. Done first: if this fails nothing else has changed,
    //    so "try again" is always safe.
    try {
      await repo.updateItem(
        itemId: widget.item.id,
        title: _titleController.text.trim(),
        description:
            _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        categoryId: _categoryId,
        latitude: _latitude,
        longitude: _longitude,
        locationLabel: _locationLabel,
        eventTime: _eventTime,
      );
    } catch (_) {
      _showMessage("Couldn't save changes. Try again.", isError: true);
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    // 2) The photos: new ones first, then removals, so a failure part-way
    //    never leaves the item with fewer photos than the person intended.
    final newFiles = [
      for (final photo in _photos)
        if (!photo.isRemote) photo.file!,
    ];
    var photosFailed = false;
    var unanalyzed = 0;

    if (newFiles.isNotEmpty || _removedImages.isNotEmpty) {
      try {
        if (newFiles.isNotEmpty) {
          final classifications = await _classify(newFiles);
          await repo.addPhotosToItem(
            itemId: widget.item.id,
            photos: newFiles,
            classifications: classifications,
          );
          unanalyzed = classifications.where((c) => c == null).length;
        }
        if (_removedImages.isNotEmpty) {
          await repo.removeItemImages(List.of(_removedImages));
        }
      } catch (e) {
        debugPrint('Updating photos failed: $e');
        photosFailed = true;
      }
    }

    if (!mounted) return;
    ref.invalidate(itemDetailProvider(widget.item.id));
    ref.invalidate(itemsFeedProvider);
    ref.invalidate(myItemsProvider);
    // A new photo can produce new matches straight away.
    ref.invalidate(matchesProvider);

    if (photosFailed) {
      // Stay on the form and show what's really saved now, so a retry
      // starts from the truth rather than re-uploading something that
      // already went through.
      _showMessage(
        "Your changes were saved, but the photos couldn't be updated. "
        'Check the photos below and try again.',
        isError: true,
      );
      setState(() {
        _isSaving = false;
        _photosLoading = true;
      });
      await _loadPhotos();
      return;
    }

    if (unanalyzed == 0) {
      _showMessage('Post updated.');
    } else {
      _showMessage(
        'Saved, but the AI could not analyze $unanalyzed new '
        'photo${unanalyzed == 1 ? '' : 's'}, so no matches can be found for '
        '${unanalyzed == 1 ? 'it' : 'them'} yet. Open Matches and tap the '
        'scan icon to retry.',
        isError: true,
      );
    }
    setState(() => _isSaving = false);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final coordsAsync = ref.watch(itemCoordinatesProvider(widget.item.id));
    coordsAsync.whenData(_primeCoordsOnce);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit post')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Photos', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_photosLoading)
              const SizedBox(height: 96, child: Center(child: CircularProgressIndicator()))
            else if (_photosLoadFailed)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Couldn't load this post's photos.",
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  TextButton(onPressed: _retryLoadPhotos, child: const Text('Retry')),
                ],
              )
            else ...[
              PhotoStrip(
                items: _photos,
                onAdd: _addPhoto,
                onRemove: _removePhotoAt,
                onReplace: _replacePhoto,
              ),
              const SizedBox(height: 8),
              Text(
                _photos.isEmpty
                    ? 'No photos — this post shows the Findora placeholder. '
                        "It's still matched by title and description; add a "
                        'photo for photo matching too.'
                    : 'Tap a photo to change it, or ✕ to remove it. '
                        'Changes apply when you save.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => InputDecorator(
                decoration: const InputDecoration(labelText: 'Category'),
                child: Text(
                  "Couldn't load categories",
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
              onPressed: _adjustLocationOnMap,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: Text(_locationLabel ?? 'Set location'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickEventTime,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                _eventTime == null
                    ? 'When was it lost/found? (optional)'
                    : DateFormat('MMM d, y · h:mm a').format(_eventTime!),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _isSaving ? null : _save,
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
    );
  }
}
