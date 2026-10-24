import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';

import 'kit.dart';
import 'languages.dart';

const navy = Color(0xFF0E1A3A);
const saffron = Color(0xFFF59E1B);

final _tts = FlutterTts();

Future<void> speak(String text, String locale) async {
  await _tts.setLanguage(locale);
  await _tts.speak(text);
}

/// Phrases to show to airport staff: [English, Japanese].
const phrases = <List<String>>[
  ['Where is the immigration counter?', '入国審査はどこですか。'],
  ['Where do I collect my baggage?', '荷物の受け取りはどこですか。'],
  ['Where is the toilet?', 'お手洗いはどこですか。'],
  ['I need a wheelchair.', '車いすをお願いします。'],
  ['Where is the transfer counter?', '乗り継ぎカウンターはどこですか。'],
  ['How do I get to the city by train or bus?', '電車やバスで市内へ行くにはどうすればいいですか。'],
  ['Where can I buy a SIM card or Wi-Fi?', 'SIMカードやWi-Fiはどこで買えますか。'],
  ['I need water.', 'お水をください。'],
  ['I need a doctor.', '医者を呼んでください。'],
  ['I lost my bag.', '荷物をなくしました。'],
  ['Please speak slowly.', 'ゆっくり話してください。'],
  ['Please write it down.', '書いていただけますか。'],
  ['I do not speak Japanese.', '日本語が話せません。'],
  ['Thank you.', 'ありがとうございます。'],
];

/// Cards to show to staff: Japanese large, English below, and the passenger's own language so they know what it says.
class CardsScreen extends StatelessWidget {
  final Profile profile;
  const CardsScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Show to staff · スタッフに見せる'), backgroundColor: navy, foregroundColor: Colors.white),
        body: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: phrases.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => Card(
            child: ListTile(
              minVerticalPadding: 14,
              title: Text(phrases[i][1], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              subtitle: Text(phrases[i][0], style: const TextStyle(fontSize: 16)),
              trailing: const Icon(Icons.open_in_full),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullCard(en: phrases[i][0], ja: phrases[i][1], profile: profile))),
            ),
          ),
        ),
      );
}

class FullCard extends StatefulWidget {
  final String en, ja;
  final Profile profile;
  const FullCard({super.key, required this.en, required this.ja, required this.profile});

  @override
  State<FullCard> createState() => _FullCardState();
}

class _FullCardState extends State<FullCard> {
  String? mine;

  @override
  void initState() {
    super.initState();
    final l = langByCode(widget.profile.lang);
    Kit.translate(widget.en, TranslateLanguage.english, l.ml ?? TranslateLanguage.english).then((v) {
      if (mounted) setState(() => mine = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = langByCode(widget.profile.lang);
    return Scaffold(
      backgroundColor: navy,
      appBar: AppBar(backgroundColor: navy, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(widget.ja, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          Text(widget.en, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFC9D1EA), fontSize: 22)),
          const SizedBox(height: 28),
          if (mine != null && l.ml != null && l.code != 'en')
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Text('${l.name}: $mine', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, color: navy)),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: saffron, foregroundColor: navy, minimumSize: const Size.fromHeight(60)),
            onPressed: () => speak(widget.ja, 'ja-JP'),
            icon: const Icon(Icons.volume_up),
            label: const Text('Play for staff · 音声で伝える', style: TextStyle(fontSize: 18)),
          ),
        ]),
      ),
    );
  }
}

/// Point the camera at a sign: read the text on the phone, translate it on the phone. No signal needed once the kit is downloaded.
class SignScreen extends StatefulWidget {
  final Profile profile;
  const SignScreen({super.key, required this.profile});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  bool japanese = true;
  File? image;
  bool busy = false;
  String note = '';
  final List<List<String>> results = []; // [original, translated]

  Future<void> run(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    setState(() {
      image = File(picked.path);
      busy = true;
      results.clear();
      note = '';
    });
    final recognizer = TextRecognizer(script: japanese ? TextRecognitionScript.japanese : TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(picked.path));
      final l = langByCode(widget.profile.lang);
      final from = japanese ? TranslateLanguage.japanese : TranslateLanguage.english;
      var to = l.ml ?? TranslateLanguage.english;
      if (l.ml == null) note = '${l.name} has no on-device translation model, so you get English.';
      var missing = false;
      for (final b in text.blocks) {
        final t = b.text.trim();
        if (t.isEmpty) continue;
        final out = await Kit.translate(t, from, to);
        if (out == null) missing = true;
        results.add([t, out ?? '(download the language kit first)']);
      }
      if (text.blocks.isEmpty) note = 'No text found. Try again closer and in good light.';
      if (missing) note = 'Some models are missing. Open "Language kit" while online once.';
    } catch (e) {
      note = 'Could not read the picture: $e';
    } finally {
      await recognizer.close();
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = langByCode(widget.profile.lang);
    return Scaffold(
      appBar: AppBar(title: const Text('Read a sign · 標識を翻訳'), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: true, label: Text('日本語 sign')), ButtonSegment(value: false, label: Text('English sign'))],
          selected: {japanese},
          onSelectionChanged: (s) => setState(() => japanese = s.first),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: busy ? null : () => run(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('Camera'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => run(ImageSource.gallery), icon: const Icon(Icons.photo), label: const Text('Gallery'))),
        ]),
        const SizedBox(height: 12),
        if (image != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(image!, height: 200, fit: BoxFit.cover)),
        if (busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (note.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(note, style: const TextStyle(color: Colors.deepOrange))),
        for (final r in results)
          Card(
            child: ListTile(
              title: Text(r[1], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              subtitle: Text(r[0]),
              trailing: IconButton(icon: const Icon(Icons.volume_up), onPressed: () => speak(r[1], l.ml == null ? 'en-US' : l.tts)),
            ),
          ),
      ]),
    );
  }
}
