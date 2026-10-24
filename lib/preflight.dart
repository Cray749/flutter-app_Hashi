import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'airport.dart' show navy, saffron;
import 'central.dart';
import 'kit.dart';
import 'languages.dart';
import 'repo.dart';

/// Phase 1, pre-flight. The booking, seat and preferences come from the passenger's account on the central backend
/// and are cached on the phone, so the screen also works with no signal. The airline's push notification is still simulated.
class PreflightScreen extends StatefulWidget {
  final Profile profile;
  final PassengerRepo repo;
  const PreflightScreen({super.key, required this.profile, required this.repo});

  @override
  State<PreflightScreen> createState() => _PreflightScreenState();
}

class _PreflightScreenState extends State<PreflightScreen> {
  bool notified = false;
  final Map<String, String> kit = {}; // model code -> state
  bool downloading = false;
  bool busy = false;
  String? error;
  late final TextEditingController central = TextEditingController(text: widget.profile.central);
  final email = TextEditingController();
  final password = TextEditingController();

  Profile get p => widget.profile;
  PassengerRepo get repo => widget.repo;

  void adopt() => applyAccountToProfile(p, repo.preferences, repo.trip);

  Future<void> signIn() async {
    setState(() { busy = true; error = null; });
    try {
      p.central = central.text.trim();
      repo.client.baseUrl = p.central;
      await repo.signIn(email.text.trim(), password.text);
      adopt();
      await p.save();
    } on CentralException catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> savePreferences() async {
    final sent = await repo.edit(preferencesFromProfile(p, repo.preferences));
    await p.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent ? 'Saved to your account' : 'Saved on this phone, will sync when there is a signal')));
    setState(() {});
  }

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

  Widget accountCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sign in to get your booking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Text('Your seat comes from your booking. You never type it.'),
            TextField(controller: central, decoration: const InputDecoration(labelText: 'Booking server address')),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton(onPressed: busy ? null : signIn, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in')),
              const SizedBox(width: 8),
              TextButton(onPressed: () => setState(() { email.text = 'demo.passenger@example.com'; password.text = 'demo-pass-123'; }), child: const Text('Fill demo account')),
            ]),
          ]),
        ),
      );

  Widget bookingCard() {
    final t = repo.trip;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.flight_takeoff, color: navy),
        title: Text(t == null ? 'No upcoming booking found' : '${t.flightNumber} · ${t.from} → ${t.to}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(t == null ? 'Check that your booking is confirmed.' : 'Seat ${t.seat} · from your booking'),
        trailing: notified ? const Icon(Icons.check_circle, color: Colors.green) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = langByCode(p.lang);
    return Scaffold(
      appBar: AppBar(title: const Text('Before you fly · ご搭乗前'), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        if (!repo.signedIn) accountCard() else bookingCard(),
        const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          FilledButton(onPressed: savePreferences, child: const Text('Save my preferences')),
          if (repo.hasPendingEdit) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Waiting for a signal: your changes are kept on this phone and will be sent later.', style: TextStyle(color: Colors.deepOrange))),
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
