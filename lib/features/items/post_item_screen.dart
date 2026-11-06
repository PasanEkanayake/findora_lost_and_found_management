import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/errors/friendly_error.dart';
import '../../core/location/countries.dart';
import '../../core/location/current_location.dart';
import '../../core/location/location_picker_screen.dart';
import '../../core/location/public_location_label.dart';
import '../../core/ml/category_mapper.dart';
import '../../core/ml/tflite_classifier.dart';
import '../../core/ml/tflite_provider.dart';
import '../../core/widgets/approximate_location_note.dart';
import '../matches/data/matches_providers.dart';
import 'data/items_providers.dart';
import '../profile/data/profile_providers.dart';
import 'data/post_draft.dart';
import 'widgets/country_field.dart';
import 'widgets/photo_strip.dart';
import 'widgets/posting_guidelines.dart';
import 'widgets/proof_question_fields.dart';

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
  final _proofQuestionController = TextEditingController();
  final _proofAnswerController = TextEditingController();
  final _picker = ImagePicker();

  String _type = 'lost';
  String? _categoryId;
  final List<File> _photos = [];

  bool _isSuggesting = false;
  String? _detectedLabel;
  double? _detectedConfidence;
  List<LabelGuess> _alternatives = const [];

  /// Below this the model is mostly guessing among many similar-sounding
  /// ImageNet classes ("can opener 23%" for a plug-in air freshener), so its
  /// best guess is not written into the Title — it is offered as a tappable
  /// suggestion instead. ImageNet spreads probability across 1000 classes, so
  /// even correct answers are often 40-70%: this is deliberately not higher.
  static const double _titleMinConfidence = 0.50;

  /// Category is a smaller, more forgiving decision (and can be changed in one
  /// tap), so it is pre-filled at a lower bar — but never with "Other", which
  /// would just look like a decision the app made.
  static const double _categoryMinConfidence = 0.30;

  // Whether the Title / Category currently showing were filled in by the
  // photo analysis (true) or have been typed/picked by the person (false).
  // Only auto-filled values may be replaced when the first photo changes —
  // anything the person chose themselves is never overwritten.
  bool _titleIsAutoFilled = false;
  bool _categoryIsAutoFilled = false;

  // Bumped for every analysis (and whenever the photo it was for goes away).
  // An analysis only applies its result if it is still the latest, so a slow
  // result for a photo that has since been swapped can't land on top of the
  // newer one.
  int _suggestionRun = 0;

  bool _isLocating = false;
  double? _latitude;
  double? _longitude;
  String? _locationLabel;

  /// ISO code of the country the item was lost/found in. Compulsory: the feed
  /// and match suggestions are per country. Pre-filled from the profile (or the
  /// phone's region) and then from the detected/picked location, until the
  /// person chooses one themselves.
  String? _countryCode;
  bool _countryIsAuto = true;

  DateTime? _eventTime;

  bool _isSubmitting = false;

  // ---- unfinished-post draft ---------------------------------------------
  static const _draftStore = PostDraftStore();
  Timer? _draftTimer;
  bool _posted = false; // once posted there is nothing left to keep

  PostDraft _currentDraft() => PostDraft(
        type: _type,
        title: _titleController.text,
        description: _descriptionController.text,
        categoryId: _categoryId,
        proofQuestion: _proofQuestionController.text,
        proofAnswer: _proofAnswerController.text,
      );

  void _scheduleDraftSave() {
    if (_posted) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), () {
      if (!_posted) _draftStore.save(_currentDraft());
    });
  }

  Future<void> _restoreDraft() async {
    final draft = await _draftStore.load();
    if (draft == null || !mounted) return;
    // Don't overwrite anything already typed in the meantime.
    if (_titleController.text.isNotEmpty || _descriptionController.text.isNotEmpty) return;
    setState(() {
      _type = draft.type;
      _titleController.text = draft.title;
      _descriptionController.text = draft.description;
      _categoryId = draft.categoryId;
      _proofQuestionController.text = draft.proofQuestion;
      _proofAnswerController.text = draft.proofAnswer;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Restored your unfinished post. Photos need to be added again.'),
        duration: const Duration(seconds: 8),
        // A snackbar with an action stays up forever unless told otherwise.
        persist: false,
        action: SnackBarAction(
          label: 'Discard',
          onPressed: () {
            _draftStore.clear();
            setState(() {
              _titleController.clear();
              _descriptionController.clear();
              _proofQuestionController.clear();
              _proofAnswerController.clear();
              _categoryId = null;
              _type = 'lost';
            });
          },
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Wakes the (optional) text-embedding service now, while the person is
    // still filling out the form — see TextEmbeddingService.warmUp.
    ref.read(textEmbeddingServiceProvider).warmUp();
    _countryCode = ref.read(myCountryProvider);
    _restoreDraft();
    // Before they fill in anything: how to keep the item private to its owner.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showPostingGuidelines(context);
    });
    for (final controller in [
      _titleController,
      _descriptionController,
      _proofQuestionController,
      _proofAnswerController,
    ]) {
      controller.addListener(_scheduleDraftSave);
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // The timer may not have fired yet — save what's there before it's gone.
    if (!_posted) _draftStore.save(_currentDraft());
    _titleController.dispose();
    _descriptionController.dispose();
    _proofQuestionController.dispose();
    _proofAnswerController.dispose();
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

  Future<void> _addPhoto() async {
    final file = await pickPhotoWithSheet(context, _picker);
    if (file == null || !mounted) return;
    final isFirstPhoto = _photos.isEmpty;
    setState(() => _photos.add(file));
    if (isFirstPhoto) _suggestCategoryFromPhoto(file);
  }

  /// Swaps the photo at [index] for a newly picked one, keeping its place.
  Future<void> _replacePhoto(int index) async {
    final file = await pickPhotoWithSheet(context, _picker);
    if (file == null || !mounted || index >= _photos.length) return;
    setState(() => _photos[index] = file);
    if (index == 0) _suggestCategoryFromPhoto(file);
  }

  /// Removes the photo at [index]. The first photo is the one the
  /// suggestions come from, so removing it re-runs the analysis on whichever
  /// photo is first now — or, with no photos left, drops the suggestion.
  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
    if (index != 0) return;
    if (_photos.isEmpty) {
      _suggestionRun++; // discard any analysis still running for the old photo
      setState(() {
        _isSuggesting = false;
        _detectedLabel = null;
        _detectedConfidence = null;
        _alternatives = const [];
        _clearAutoFilledFields();
      });
    } else {
      _suggestCategoryFromPhoto(_photos.first);
    }
  }

  /// Empties Title/Category, but only if they still hold a value the photo
  /// analysis put there. Call inside setState.
  void _clearAutoFilledFields() {
    if (_titleIsAutoFilled) {
      _titleController.clear();
      _titleIsAutoFilled = false;
    }
    if (_categoryIsAutoFilled) {
      _categoryId = null;
      _categoryIsAutoFilled = false;
    }
  }

  /// Runs the on-device model on the first photo purely for a live
  /// "Detected: X" suggestion — never blocks the form, and fails silently
  /// (logged via debugPrint) if the model asset isn't in place yet.
  ///
  /// Runs again every time the first photo changes. Title and Category are
  /// refreshed to match the new photo **unless the person has typed/picked
  /// their own value**: before, they were only ever filled while empty, so
  /// the first photo's guess stuck even after the photo was swapped.
  Future<void> _suggestCategoryFromPhoto(File file) async {
    final run = ++_suggestionRun;
    setState(() => _isSuggesting = true);
    try {
      final classifier = await ref.read(tfliteClassifierProvider.future);
      final result = await classifier.classify(file);
      if (!mounted || run != _suggestionRun) return;
      setState(() {
        _detectedLabel = result.label;
        _detectedConfidence = result.confidence;
        _alternatives = result.alternatives;
      });

      // TITLE — only a confident guess is written in. Either way, a title
      // the previous photo's analysis put there is cleared if this photo
      // doesn't earn a new one (it would describe the wrong photo). A title
      // the person typed is never touched — including someone who started
      // typing before the model finished.
      final confident = result.confidence >= _titleMinConfidence;
      if (_titleController.text.trim().isEmpty || _titleIsAutoFilled) {
        if (confident) {
          _titleController.text = _titleCaseFromLabel(result.label);
          _titleIsAutoFilled = true;
        } else if (_titleIsAutoFilled) {
          _titleController.clear();
          _titleIsAutoFilled = false;
        }
      }

      // CATEGORY — same rule, lower bar, and never "Other".
      if (_categoryId == null || _categoryIsAutoFilled) {
        final suggestedName = mapImagenetLabelToCategory(result.label);
        final categories = await ref.read(categoriesProvider.future);
        if (!mounted || run != _suggestionRun) return;
        // The person may have picked a category while categories loaded.
        if (_categoryId == null || _categoryIsAutoFilled) {
          String? suggestedId;
          if (result.confidence >= _categoryMinConfidence && suggestedName != 'Other') {
            for (final category in categories) {
              if (category.name == suggestedName) {
                suggestedId = category.id;
                break;
              }
            }
          }
          setState(() {
            _categoryId = suggestedId;
            _categoryIsAutoFilled = suggestedId != null;
          });
        }
      }
    } catch (e) {
      debugPrint('Category suggestion skipped (model not ready?): $e');
    } finally {
      // Only the latest run owns the spinner.
      if (mounted && run == _suggestionRun) setState(() => _isSuggesting = false);
    }
  }

  /// The person tapped one of the suggestion chips: that is their choice, so
  /// it counts as typed (never overwritten by a later analysis), and the
  /// category follows it unless they have already picked their own.
  Future<void> _applySuggestion(String label) async {
    _titleController.text = _titleCaseFromLabel(label);
    _titleIsAutoFilled = false;
    if (_categoryId == null || _categoryIsAutoFilled) {
      final name = mapImagenetLabelToCategory(label);
      if (name != 'Other') {
        final categories = await ref.read(categoriesProvider.future);
        if (!mounted) return;
        for (final category in categories) {
          if (category.name == name) {
            setState(() {
              _categoryId = category.id;
              _categoryIsAutoFilled = true;
            });
            break;
          }
        }
      }
    }
  }

  /// "cellular_telephone" -> "Cellular Telephone" — a plain ImageNet label
  /// isn't a title on its own, but it's a reasonable starting point the
  /// person can edit rather than typing one from scratch.
  String _titleCaseFromLabel(String rawLabel) {
    return rawLabel
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
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
      String? detectedCountry;
      try {
        // geocoding 5.x replaced the old top-level placemarkFromCoordinates()
        // function with an instance method on the Geocoding class.
        final placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          detectedCountry = p.isoCountryCode?.toUpperCase();
          // Shown to other people, so a neighbourhood or town — never the street.
          label = publicLocationLabel(
            subLocality: p.subLocality,
            locality: p.locality,
            administrativeArea: p.administrativeArea,
          );
        }
      } catch (_) {
        // Reverse geocoding can fail independently of getting a fix — the
        // coordinates are still useful even without a friendly label.
      }
      if (!mounted) return;

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationLabel = label;
        _applyLocationCountry(detectedCountry);
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Opens LocationPickerScreen to fine-tune the pin dropped by
  /// [_detectLocation] (or, if the person hasn't auto-detected yet, starts
  /// centered on a reasonable fallback so "adjust manually" still works
  /// without GPS ever having run).
  Future<void> _adjustLocationOnMap() async {
    // Null is fine — the picker then finds the device's position itself
    // rather than opening on (0, 0), which is open ocean.
    final startLat = _latitude;
    final startLng = _longitude;

    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialLatitude: startLat, initialLongitude: startLng),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;
      _locationLabel = picked.label;
      _applyLocationCountry(picked.countryCode);
    });
  }

  /// A detected/picked location knows its country — use it, unless the person
  /// has already chosen one by hand. Call inside setState.
  void _applyLocationCountry(String? isoCode) {
    if (isoCode != null && isKnownCountry(isoCode) && _countryIsAuto) {
      _countryCode = isoCode.toUpperCase();
    }
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
    // Photos are optional — only the title is required (checked by the
    // form validator above). An item posted without one is shown with the
    // Findora placeholder instead, and the AI can still match it by title
    // and description (see 12_text_matching.sql); adding a photo later via
    // Edit adds photo matching on top of that.

    setState(() => _isSubmitting = true);
    try {
      final classifications = await _classifyAllPhotos();

      // Best-effort and fully optional — see TextEmbeddingService's doc.
      // Run after photo classification (not in parallel with it) so a
      // slow/cold-starting AI service can't also compete with on-device
      // inference for the same CPU cores.
      final textEmbedding = await ref.read(textEmbeddingServiceProvider).tryEmbed(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
          );

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
            eventTime: _eventTime,
            textEmbedding: textEmbedding,
            // Only found items carry a proof question.
            proofQuestion: _type == 'found' ? _proofQuestionController.text : null,
            proofAnswer: _type == 'found' ? _proofAnswerController.text : null,
            countryCode: _countryCode!, // the form validator guarantees it
          );

      // Posted: the saved draft has done its job.
      _posted = true;
      _draftTimer?.cancel();
      _draftStore.clear();

      if (!mounted) return;
      ref.invalidate(itemsFeedProvider);
      // The record_matches_for_image trigger runs synchronously as part of
      // the item_images insert above, so any matches already exist by now.
      ref.invalidate(matchesProvider);

      // Posting deliberately doesn't fail just because the AI couldn't
      // analyze a photo — but it used to say nothing at all, and a photo
      // with no embedding can never be matched. Say so, and point at the
      // retry (MatchesScreen re-scans photos that are missing one).
      final unanalyzed = classifications.where((c) => c == null).length;
      if (unanalyzed > 0) {
        _showMessage(
          'Posted, but the AI could not analyze $unanalyzed '
          'photo${unanalyzed == 1 ? '' : 's'}, so no matches can be found yet. '
          'Open Matches and tap the scan icon to retry.',
          isError: true,
        );
      }
      context.pop();
    } catch (e) {
      _showMessage(
        friendlyDatabaseError(
          e,
          fallback: 'Could not post this item. Check your connection and try again.',
        ),
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
          tooltip: 'Close',
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showPostingGuidelines(context, force: true),
                  icon: const Icon(Icons.tips_and_updates_outlined, size: 18),
                  label: const Text('Posting tips'),
                ),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'lost', label: Text('I lost this')),
                  ButtonSegment(value: 'found', label: Text('I found this')),
                ],
                selected: {_type},
                onSelectionChanged: (value) {
                  setState(() => _type = value.first);
                  _scheduleDraftSave();
                },
              ),
              const SizedBox(height: 20),
              PhotoStrip(
                items: [for (final photo in _photos) PhotoStripItem.local(photo)],
                onAdd: _addPhoto,
                onRemove: _removePhoto,
                onReplace: _replacePhoto,
              ),
              const SizedBox(height: 8),
              Text(
                _photos.isEmpty
                    ? 'Photos are optional — the AI already matches by title and '
                        "description. Add one and it'll match by photo too."
                    : 'Tap a photo to change it.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (_isSuggesting || _detectedLabel != null) ...[
                const SizedBox(height: 10),
                _DetectionBadge(
                  isLoading: _isSuggesting,
                  label: _detectedLabel,
                  confidence: _detectedConfidence,
                  confident: (_detectedConfidence ?? 0) >= _titleMinConfidence,
                  alternatives: _alternatives,
                  onPick: _applySuggestion,
                ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Title'),
                // onChanged only fires for the person's own typing, not for
                // the analysis setting .text — so this is what tells the two
                // apart.
                onChanged: (_) => _titleIsAutoFilled = false,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'A title is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
              ),
              if (_type == 'found') ...[
                const SizedBox(height: 16),
                ProofQuestionFields(
                  questionController: _proofQuestionController,
                  answerController: _proofAnswerController,
                ),
              ],
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
                  // initialValue is only read when the field is created, so a
                  // category set by the photo analysis (or by tapping a
                  // suggestion) after the field exists would not show up.
                  // Re-keying on the value rebuilds it with the new one.
                  key: ValueKey('category-$_categoryId'),
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (value) => setState(() {
                    _categoryId = value;
                    _categoryIsAutoFilled = false;
                  }),
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
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _adjustLocationOnMap,
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: Text(_latitude == null ? 'Set location manually' : 'Adjust pin on map'),
              ),
              const ApproximateLocationNote(),
              const SizedBox(height: 16),
              CountryField(
                value: _countryCode,
                onChanged: (code) => setState(() {
                  _countryCode = code;
                  _countryIsAuto = false;
                }),
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
  const _DetectionBadge({
    required this.isLoading,
    required this.confident,
    required this.alternatives,
    required this.onPick,
    this.label,
    this.confidence,
  });

  final bool isLoading;
  final String? label;
  final double? confidence;

  /// Whether the best guess was sure enough to be written into the form.
  final bool confident;

  /// The model's top guesses, offered as chips when it isn't confident.
  final List<LabelGuess> alternatives;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = confidence == null ? '' : ' (${(confidence! * 100).round()}%)';

    final String message;
    if (isLoading) {
      message = 'Analyzing photo…';
    } else if (confident) {
      message = 'Detected: ${_prettify(label!)}$percent — title and category '
          'pre-filled below, change them if needed.';
    } else {
      message = "Not sure what this is (best guess: ${_prettify(label!)}$percent). "
          'Pick a suggestion, or type your own title.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
            ],
          ),
          if (!isLoading && !confident && alternatives.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final guess in alternatives)
                  ActionChip(
                    label: Text(_prettify(guess.label)),
                    onPressed: () => onPick(guess.label),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _prettify(String rawLabel) {
    return rawLabel.replaceAll('_', ' ');
  }
}
