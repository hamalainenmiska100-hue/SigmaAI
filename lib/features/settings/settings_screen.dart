import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/widgets/section_title.dart';
import 'services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService(LocalStorageService());
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _service.loadCustomInstructions();
    if (!mounted) return;
    _controller.text = value;
  }

  Future<void> _save() async {
    await _service.saveCustomInstructions(_controller.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferences saved')));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: 'Assistant behavior'),
          const SizedBox(height: 8),
          Text(
            'System guidance sent with each request.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 6,
            maxLines: 10,
            maxLength: AppConfig.maxCustomInstructionsLength,
            decoration: const InputDecoration(
              hintText: 'Example: Keep answers concise and include bullet points.',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save Settings'),
            ),
          ),
        ],
      ),
    );
  }
}
