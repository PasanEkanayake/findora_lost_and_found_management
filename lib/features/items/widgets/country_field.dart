import 'package:flutter/material.dart';

import '../../../core/location/countries.dart';
import '../../../core/location/country_picker.dart';

/// The compulsory "Country" row of the post/edit form. Tapping it opens the
/// searchable country list. Validation fails (red message under the row) until
/// a country is chosen, so a post can't be submitted without one — the feed
/// and match suggestions are filtered by country, so a post without it would
/// be invisible to everyone.
class CountryField extends FormField<String> {
  CountryField({
    super.key,
    required String? value,
    required ValueChanged<String> onChanged,
    String label = 'Country (required)',
    String helper = 'The country where it was lost or found',
  }) : super(
          initialValue: value,
          validator: (current) =>
              (current == null || !isKnownCountry(current)) ? 'Please choose the country' : null,
          builder: (state) {
            // The parent owns the value; keep this field's copy in step so the
            // row, the validator and form.save() all agree.
            if (state.value != value) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (state.mounted) state.didChange(value);
              });
            }
            final theme = Theme.of(state.context);
            final label = countryLabel(value);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showCountryPicker(state.context, selected: value);
                    if (picked != null) {
                      onChanged(picked);
                      state.didChange(picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: label,
                      helperText: helper,
                      errorText: state.errorText,
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(
                      label.isEmpty ? 'Choose a country' : label,
                      style: label.isEmpty
                          ? theme.textTheme.bodyLarge
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                          : theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ],
            );
          },
        );
}
