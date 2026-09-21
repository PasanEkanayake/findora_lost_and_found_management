import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/location/location_picker_screen.dart';
import 'data/item_model.dart';
import 'data/items_providers.dart';

/// Editing an existing item — title/description/category/location/event
/// time, not photos or lost-vs-found type. See
/// ItemsRepository.updateItem's doc for why those two are deliberately
/// out of scope here.
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

  @override
  void initState() {
    super.initState();
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
    try {
      await ref.read(itemsRepositoryProvider).updateItem(
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
      ref.invalidate(itemDetailProvider(widget.item.id));
      ref.invalidate(itemsFeedProvider);
      ref.invalidate(myItemsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post updated.')));
      context.pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't save changes. Try again.")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
