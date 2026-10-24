import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'airport.dart' show navy, saffron;
import 'kit.dart';

/// Phase 2 and 3: join the aircraft's local network (the crew laptop hotspot in the demo) and open the cabin app,
/// with the saved profile carried in the address so the passenger does not set it up twice.
class CabinScreen extends StatefulWidget {
  final Profile profile;
  const CabinScreen({super.key, required this.profile});

  @override
  State<CabinScreen> createState() => _CabinScreenState();
}

class _CabinScreenState extends State<CabinScreen> {
  late final TextEditingController server = TextEditingController(text: widget.profile.server);
  WebViewController? web;

  void open() {
    widget.profile.server = server.text.trim();
    widget.profile.save();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.profile.cabinUrl()));
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnPlatformPermissionRequest((request) => request.grant());
    }
    setState(() => web = c);
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
          actions: [IconButton(icon: const Icon(Icons.open_in_browser), tooltip: 'Open in browser (microphone)', onPressed: () => launchUrl(Uri.parse(widget.profile.cabinUrl()), mode: LaunchMode.externalApplication))],
        ),
        body: WebViewWidget(controller: web!),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Join the cabin · 機内に接続'), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text('Connect this phone to the aircraft Wi-Fi first (in the demo: the crew laptop hotspot), then open the cabin app. Your language and needs are passed along.'),
        const SizedBox(height: 12),
        TextField(controller: server, decoration: const InputDecoration(labelText: 'Cabin server address', helperText: 'The crew tablet shows this under QR')),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: saffron, foregroundColor: navy, minimumSize: const Size.fromHeight(56)),
          onPressed: open,
          icon: const Icon(Icons.flight),
          label: const Text('Open the cabin app', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.parse(widget.profile.cabinUrl()), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open in the phone browser (use this for the microphone)'),
        ),
        const Divider(height: 32),
        const Text('My profile QR (language, text size and needs, no name):'),
        const SizedBox(height: 8),
        Center(child: QrImageView(data: widget.profile.cabinUrl(), size: 220)),
      ]),
    );
  }
}
