import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'languages.dart';

/// Saved passenger profile (kept on the phone only).
class Profile {
  String lang;
  String seat;
  bool senior;
  Set<String> needs;
  String server;
  String central;
  /// The seat comes from the booking and is never typed. Empty until the booking has been read.
  Profile({this.lang = 'ta', this.seat = '', this.senior = false, Set<String>? needs, this.server = 'http://192.168.137.1:8000', this.central = 'http://192.168.137.1:8100'})
      : needs = needs ?? {};

  static Future<Profile> load() async {
    final p = await SharedPreferences.getInstance();
    return Profile(
      lang: p.getString('lang') ?? 'ta',
      seat: p.getString('seat') ?? '',
      senior: p.getBool('senior') ?? false,
      needs: (p.getStringList('needs') ?? []).toSet(),
      server: p.getString('server') ?? 'http://192.168.137.1:8000',
      central: p.getString('central') ?? 'http://192.168.137.1:8100',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', lang);
    await p.setString('seat', seat);
    await p.setBool('senior', senior);
    await p.setStringList('needs', needs.toList());
    await p.setString('server', server);
    await p.setString('central', central);
  }

  /// Address of the cabin web app, with the profile in the URL fragment so it never reaches a server log.
  String cabinUrl() {
    final frag = 'lang=$lang&senior=${senior ? 1 : 0}&needs=${needs.join(',')}';
    final query = seat.isEmpty ? '' : '?seat=$seat';
    return '${server.replaceAll(RegExp(r'/+$'), '')}/p/$query#$frag';
  }
}

/// On-device translation through ML Kit. Models are downloaded once (on Wi-Fi at home) and then work with no signal.
class Kit {
  static final _manager = OnDeviceTranslatorModelManager();

  /// The two-letter codes of languages this phone can translate for [lang] (always Japanese and English too).
  static List<TranslateLanguage> needed(String lang) {
    final l = langByCode(lang);
    return {TranslateLanguage.japanese, TranslateLanguage.english, if (l.ml != null) l.ml!}.toList();
  }

  static Future<bool> has(TranslateLanguage l) => _manager.isModelDownloaded(l.bcpCode);

  static Future<bool> download(TranslateLanguage l) => _manager.downloadModel(l.bcpCode, isWifiRequired: false);

  /// Translate text. Returns null when the model is missing or the pair is not supported.
  static Future<String?> translate(String text, TranslateLanguage from, TranslateLanguage to) async {
    if (from == to || text.trim().isEmpty) return text;
    if (!await has(from) || !await has(to)) return null;
    final t = OnDeviceTranslator(sourceLanguage: from, targetLanguage: to);
    try {
      return await t.translateText(text);
    } finally {
      await t.close();
    }
  }
}
