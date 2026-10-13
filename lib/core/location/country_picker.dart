import 'package:flutter/material.dart';

import 'countries.dart';

/// A searchable bottom sheet of countries. Resolves to the chosen ISO code,
/// or null if dismissed. [selected] is ticked and scrolled to the top.
Future<String?> showCountryPicker(
  BuildContext context, {
  String? selected,
  String? title,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _CountryPickerSheet(selected: selected, title: title),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.selected, this.title});

  final String? selected;
  final String? title;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = searchCountries(_query);
    final selected = widget.selected?.toUpperCase();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              if (widget.title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(widget.title!, style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search countries',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: results.isEmpty
                    ? const Center(child: Text('No country found'))
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final country = results[index];
                          final isSelected = country.code == selected;
                          return ListTile(
                            leading: Text(
                              flagEmoji(country.code),
                              style: const TextStyle(fontSize: 24),
                            ),
                            title: Text(country.name),
                            trailing: isSelected ? const Icon(Icons.check) : null,
                            selected: isSelected,
                            onTap: () => Navigator.pop(context, country.code),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
