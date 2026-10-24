import 'package:flutter/material.dart';

import 'airport.dart';
import 'cabin.dart';
import 'kit.dart';
import 'languages.dart';
import 'preflight.dart';
import 'repo.dart';
import 'theme.dart';

void main() => runApp(const HashiApp());

class HashiApp extends StatelessWidget {
  /// Tests pass their own home screen; the app itself uses [Home].
  final Widget? home;
  const HashiApp({super.key, this.home});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HASHI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: home ?? const Home(),
      );
}

/// The passenger's journey in four steps: before you fly, boarding and the cabin, the airport and city, and your kit.
class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Profile? profile;
  PassengerRepo? repo;

  @override
  void initState() {
    super.initState();
    Profile.load().then((p) async {
      final r = await PassengerRepo.open(p.central);
      applyAccountToProfile(p, r.preferences, r.trip);
      if (mounted) setState(() { profile = p; repo = r; });
      // pick up changes made elsewhere when there is a signal; silent when there is none
      if (await r.refresh() && mounted) setState(() => applyAccountToProfile(p, r.preferences, r.trip));
    });
  }

  void go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) => setState(() {}));

  Widget step(IconData icon, String title, String subtitle, VoidCallback onTap, {Color? color}) => Card(
        color: color,
        child: ListTile(
          minVerticalPadding: 16,
          leading: CircleAvatar(backgroundColor: navy, foregroundColor: Colors.white, child: Icon(icon)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final r = repo;
    if (p == null || r == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final l = langByCode(p.lang);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text('HASHI 橋 · पुल · ਪੁਲ'),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Text(l.name, style: const TextStyle(fontSize: 16))))],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text("Don't translate. Understand.", style: TextStyle(fontSize: 20, fontStyle: FontStyle.italic)),
        const SizedBox(height: 4),
        Text('${p.seat.isEmpty ? 'Seat comes from your booking' : 'Seat ${p.seat}'} · ${l.name}${p.senior ? ' · bigger text' : ''}'),
        const SizedBox(height: 12),
        step(Icons.event_available, '1 · Before you fly', 'Booking, preferences, language kit', () => go(PreflightScreen(profile: p, repo: r))),
        step(Icons.flight, '2 · On the aircraft', 'Join the cabin network and talk to the crew', () => go(CabinScreen(profile: p, repo: r))),
        step(Icons.camera_alt, '3 · After landing: read a sign', 'Camera to text to your language, no signal needed', () => go(SignScreen(profile: p)), color: const Color(0xFFFDF0D5)),
        step(Icons.record_voice_over, '3 · After landing: show staff', 'Japanese cards with sound', () => go(CardsScreen(profile: p))),
        const SizedBox(height: 16),
        const Text('Your data stays on this phone. Nothing is sent anywhere unless you join the cabin network.', style: TextStyle(color: Colors.black54)),
      ]),
    );
  }
}
