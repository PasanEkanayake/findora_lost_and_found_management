import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/supabase/supabase_client.dart';

/// "Download my data": asks the database for everything Findora holds about
/// the signed-in person (`export_my_data()` in supabase/25_outcomes_and_data_export.sql)
/// as one JSON document, which can then be copied and kept or pasted into an
/// email. There's no file/share plugin in the app, so copying is the way out.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool _loading = false;
  String? _json;
  String? _error;

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await supabase.rpc('export_my_data');
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      setState(() => _json = pretty);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't prepare your data. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _json!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied. Paste it somewhere safe.')),
    );
  }

  String _size(String text) {
    final bytes = utf8.encode(text).length;
    return bytes < 1024 ? '$bytes bytes' : '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final json = _json;

    return Scaffold(
      appBar: AppBar(title: const Text('Download my data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'This prepares a copy of everything Findora holds about your account: your '
            'profile, posts, matches, messages, claims, ratings and alerts. Other people '
            'appear only as ids, and your push tokens are not included.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _prepare,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(json == null ? 'Prepare my data' : 'Prepare again'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (json != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Ready — ${_size(json)}', style: theme.textTheme.titleSmall),
                ),
                OutlinedButton.icon(
                  onPressed: _copy,
                  // Not full-width (the theme default) — this sits in a Row.
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                // A preview — the whole document is what gets copied.
                json.length > 3000 ? '${json.substring(0, 3000)}\n… (preview — Copy gives you everything)' : json,
                style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
