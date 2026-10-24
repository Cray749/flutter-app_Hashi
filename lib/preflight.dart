import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'airport.dart' show navy, saffron;
import 'kit.dart';
import 'languages.dart';

/// Phase 1, pre-flight. The booking and the notification are SIMULATED (there is no airline API);
/// the preferences are saved on the phone and the language kit download is real.
class PreflightScreen extends StatefulWidget {
  final Profile profile;
  const PreflightScreen({super.key, required this.profile});

  @override
  State<PreflightScreen> createState() => _PreflightScreenState();
}

class _PreflightScreenState extends State<PreflightScreen> {
  bool notified = false;
  final Map<String, String> kit = {}; // model code -> state
  bool downloading = false;

  Profile get p => widget.profile;

  Future<void> downloadKit() async {
    setState(() => downloading = true);
    for (final l in Kit.needed(p.lang)) {
      setState(() => kit[l.bcpCode] = 'downloading');
      try {
        final ok = await Kit.has(l) || await Kit.download(l);
        setState(() => kit[l.bcpCode] = ok ? 'ready' : 'failed');
      } catch (_) {
        setState(() => kit[l.bcpCode] = 'failed');
      }
    }
    setState(() => downloading = false);
  }

  String label(String code) => {
        TranslateLanguage.japanese.bcpCode: '日本語 Japanese',
        TranslateLanguage.english.bcpCode: 'English',
      }[code] ??
      langByCode(p.lang).name;

  @override
  Widget build(BuildContext context) {
    final l = langByCode(p.lang);
    return Scaffold(
      appBar: AppBar(title: const Text('Before you fly · ご搭乗前'), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Chip(label: Text('Simulated booking: no airline system is connected'), avatar: Icon(Icons.info_outline)),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.flight_takeoff, color: navy),
            title: const Text('Booking confirmed · Delhi → Tokyo', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Seat ${p.seat} assigned'),
            trailing: notified ? const Icon(Icons.check_circle, color: Colors.green) : null,
          ),
        ),
        if (!notified)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: saffron, foregroundColor: navy),
            onPressed: () => setState(() => notified = true),
            icon: const Icon(Icons.notifications_active),
            label: const Text('Show the notification the passenger would get'),
          ),
        if (notified) ...[
          Card(
            color: const Color(0xFFFDF0D5),
            child: const ListTile(
              leading: Icon(Icons.notifications, color: navy),
              title: Text('Tell the crew how to help you'),
              subtitle: Text('Set your language and needs, and get your language kit for the flight.'),
            ),
          ),
          const SizedBox(height: 8),
          Text('1 · Your language', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in languages)
              ChoiceChip(label: Text(x.name), selected: p.lang == x.code, onSelected: (_) => setState(() => p.lang = x.code)),
          ]),
          const SizedBox(height: 14),
          Text('2 · What helps you', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(title: const Text('Bigger text and pictures'), value: p.senior, onChanged: (v) => setState(() => p.senior = v)),
          for (final n in const {'veg': 'Vegetarian', 'hearing': 'I hear less well', 'mobility': 'I need help walking'}.entries)
            CheckboxListTile(
              title: Text(n.value),
              value: p.needs.contains(n.key),
              onChanged: (v) => setState(() => v == true ? p.needs.add(n.key) : p.needs.remove(n.key)),
            ),
          TextFormField(initialValue: p.seat, decoration: const InputDecoration(labelText: 'Seat (from your booking)'), onChanged: (v) => p.seat = v.toUpperCase()),
          const SizedBox(height: 12),
          FilledButton(onPressed: () async { await p.save(); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved on this phone'))); }, child: const Text('Save my preferences')),
          const Divider(height: 32),
          Text('3 · Language kit for ${l.name}', style: Theme.of(context).textTheme.titleMedium),
          const Text('Small translation models stay on your phone so the camera translator works with no signal. Download them now, on Wi-Fi.'),
          if (l.ml == null) Text('${l.name} has no on-device model: signs will be translated to English.', style: const TextStyle(color: Colors.deepOrange)),
          const SizedBox(height: 8),
          for (final m in Kit.needed(p.lang))
            ListTile(
              leading: switch (kit[m.bcpCode]) {
                'ready' => const Icon(Icons.check_circle, color: Colors.green),
                'downloading' => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                'failed' => const Icon(Icons.error, color: Colors.red),
                _ => const Icon(Icons.download_for_offline_outlined),
              },
              title: Text(label(m.bcpCode)),
              subtitle: Text(kit[m.bcpCode] ?? 'not downloaded'),
            ),
          FilledButton.icon(onPressed: downloading ? null : downloadKit, icon: const Icon(Icons.download), label: const Text('Download language kit')),
        ],
      ]),
    );
  }
}
