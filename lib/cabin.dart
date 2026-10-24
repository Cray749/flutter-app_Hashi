import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'airport.dart' show navy, saffron;
import 'discover.dart';
import 'kit.dart';
import 'repo.dart';

/// Phase 2 and 3: the phone looks for the aircraft network by itself, boards with the signed pass from the booking
/// (so the crew see the seat and preferences without anyone typing them), and opens the cabin app.
class CabinScreen extends StatefulWidget {
  final Profile profile;
  final PassengerRepo repo;
  /// Replaceable in tests.
  final Future<CabinConnection> Function(List<String> hosts)? connector;
  final Duration retryEvery;
  const CabinScreen({super.key, required this.profile, required this.repo, this.connector, this.retryEvery = const Duration(seconds: 5)});

  @override
  State<CabinScreen> createState() => _CabinScreenState();
}

class _CabinScreenState extends State<CabinScreen> {
  final manualAddress = TextEditingController();
  CabinConnection? connection;
  bool searching = false;
  bool showManual = false;
  WebViewController? web;
  Timer? timer;

  Profile get p => widget.profile;

  @override
  void initState() {
    super.initState();
    search();
    timer = Timer.periodic(widget.retryEvery, (_) {
      if (connection?.connected != true && !searching) search();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> search() async {
    if (!mounted) return;
    setState(() => searching = true);
    final hosts = defaultCabinHosts(lastGood: p.server.isEmpty ? null : p.server, fromQr: manualAddress.text.trim().isEmpty ? null : manualAddress.text.trim());
    final result = await (widget.connector ??
        (h) => connectToCabin(hosts: h, getGrant: widget.repo.boardingGrant, deviceId: widget.repo.deviceId, bookedSeat: p.seat.isEmpty ? null : p.seat))(hosts);
    if (!mounted) return;
    setState(() {
      connection = result;
      searching = false;
    });
    if (result.connected) {
      p.server = result.baseUrl!;
      if (result.seat != null) p.seat = result.seat!;
      await p.save();
    }
  }

  void open() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(p.cabinUrl()));
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnPlatformPermissionRequest((request) => request.grant());
    }
    setState(() => web = c);
  }

  ({IconData icon, Color color, String title, String detail}) status() {
    final c = connection;
    if (searching && c == null) return (icon: Icons.wifi_find, color: Colors.orange, title: 'Looking for the cabin…', detail: 'Connect to the aircraft Wi-Fi. This page keeps trying by itself.');
    switch (c?.state) {
      case CabinState.ready:
        return (icon: Icons.check_circle, color: Colors.green, title: 'Connected${c!.flight?.isNotEmpty == true ? ' to ${c.flight}' : ''} · seat ${c.seat ?? p.seat}', detail: 'The crew can see your language and needs.');
      case CabinState.readyWithoutPass:
        return (icon: Icons.check_circle_outline, color: Colors.green, title: 'Connected to the cabin · seat ${c!.seat ?? p.seat}', detail: 'This cabin server does not take boarding passes yet, so your booked seat is used.');
      case CabinState.noPass:
        return (icon: Icons.warning_amber, color: Colors.deepOrange, title: 'Cabin found, but no boarding pass', detail: 'Open the app with internet once before the flight, on the "Before you fly" step, to get your pass.');
      case CabinState.refused:
        return (icon: Icons.block, color: Colors.red, title: 'The cabin did not accept the pass', detail: c?.message ?? 'Ask the crew for help.');
      case CabinState.seatTaken:
        return (icon: Icons.event_seat, color: Colors.red, title: 'Another phone is using your seat', detail: 'Please tell a crew member.');
      case CabinState.unreachable:
        return (icon: Icons.wifi_off, color: Colors.deepOrange, title: 'The cabin did not answer', detail: c?.message ?? 'Trying again…');
      default:
        return (icon: Icons.wifi_off, color: Colors.deepOrange, title: 'Cabin not found yet', detail: 'Check you are on the aircraft Wi-Fi. Your cards and sign reader still work offline.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (web != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cabin · 機内'),
          backgroundColor: navy,
          foregroundColor: Colors.white,
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => web = null)),
          actions: [IconButton(icon: const Icon(Icons.open_in_browser), tooltip: 'Open in browser (microphone)', onPressed: () => launchUrl(Uri.parse(p.cabinUrl()), mode: LaunchMode.externalApplication))],
        ),
        body: WebViewWidget(controller: web!),
      );
    }
    final s = status();
    final c = connection;
    return Scaffold(
      appBar: AppBar(title: const Text('Join the cabin · 機内に接続'), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Card(
          child: ListTile(
            leading: searching ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)) : Icon(s.icon, color: s.color, size: 32),
            title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(s.detail),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: saffron, foregroundColor: navy, minimumSize: const Size.fromHeight(56)),
          onPressed: c?.connected == true ? open : null,
          icon: const Icon(Icons.flight),
          label: const Text('Open the cabin app', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: c?.connected == true ? () => launchUrl(Uri.parse(p.cabinUrl()), mode: LaunchMode.externalApplication) : null,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open in the phone browser (use this for the microphone)'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: searching ? null : search, child: const Text('Try again now')),
        if (c != null && !c.connected)
          TextButton(onPressed: () => setState(() => showManual = !showManual), child: Text(showManual ? 'Hide the address box' : 'Cabin not found? Enter the address from the crew')),
        if (showManual) TextField(controller: manualAddress, decoration: const InputDecoration(labelText: 'Cabin address', helperText: 'Shown by the crew under the QR code')),
        const Divider(height: 32),
        const Text('My profile QR (language, text size and needs, no name):'),
        const SizedBox(height: 8),
        Center(child: QrImageView(data: p.cabinUrl(), size: 220)),
      ]),
    );
  }
}
