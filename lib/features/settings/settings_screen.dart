import 'package:flutter/material.dart';

import '../../core/widgets/section_title.dart';
import '../../core/storage/local_storage_service.dart';
import 'services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService(LocalStorageService());

  AssistantLanguage _language = AssistantLanguage.english;
  AssistantTone _tone = AssistantTone.normal;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _service.loadSettings();
    if (!mounted) return;
    setState(() {
      _language = settings.language;
      _tone = settings.tone;
      _loading = false;
    });
  }

  Future<void> _saveLanguage(AssistantLanguage language) async {
    setState(() => _language = language);
    await _service.saveLanguage(language);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Language updated')));
  }

  Future<void> _saveTone(AssistantTone tone) async {
    setState(() => _tone = tone);
    await _service.saveTone(tone);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Style updated')));
  }

  String _languageLabel(AssistantLanguage language) {
    switch (language) {
      case AssistantLanguage.english:
        return 'English';
      case AssistantLanguage.swedish:
        return 'Swedish';
      case AssistantLanguage.finnish:
        return 'Finnish';
    }
  }

  String _toneLabel(AssistantTone tone) {
    switch (tone) {
      case AssistantTone.normal:
        return 'Normal';
      case AssistantTone.unhinged:
        return 'Unhinged';
      case AssistantTone.spicy:
        return 'Spicy';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionTitle(title: 'Language'),
                const SizedBox(height: 8),
                DropdownButtonFormField<AssistantLanguage>(
                  value: _language,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    helperText: 'Appends a hidden tag to your prompt for the AI.',
                  ),
                  items: AssistantLanguage.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_languageLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    _saveLanguage(value);
                  },
                ),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Style customization'),
                const SizedBox(height: 8),
                DropdownButtonFormField<AssistantTone>(
                  value: _tone,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    helperText: 'Controls which server system instruction profile is used.',
                  ),
                  items: AssistantTone.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_toneLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    _saveTone(value);
                  },
                ),
              ],
            ),
    );
  }
}
