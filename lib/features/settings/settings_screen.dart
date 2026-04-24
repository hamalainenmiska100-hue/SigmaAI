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
  final _nameController = TextEditingController();
  double _bubbleRadius = 24;

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
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customize Sigma')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: 'Profile'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: 'Display name (local)'),
          ),
          const SizedBox(height: 18),
          const SectionTitle(title: 'Look & Feel'),
          const SizedBox(height: 6),
          Text('Bubble roundness ${_bubbleRadius.round()}'),
          Slider(
            value: _bubbleRadius,
            min: 14,
            max: 36,
            onChanged: (v) => setState(() => _bubbleRadius = v),
          ),
          const SizedBox(height: 18),
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
              child: const Text('Save Preferences'),
            ),
          ),
        ],
      ),
    );
  }
}
