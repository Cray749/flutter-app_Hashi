import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/cabin_link.dart';
import 'package:hashi_mobile/content.dart';
import 'package:hashi_mobile/kit.dart';
import 'package:hashi_mobile/session.dart';
import 'package:stream_channel/stream_channel.dart';

/// Loads the bundled wording straight from the asset files, so widget tests see the same words as the phone.
void loadContentForTests() {
  Content.instance = Content.parse(
    ui: File('assets/cards/ui.json').readAsStringSync(),
    replies: File('assets/cards/replies.json').readAsStringSync(),
    announcements: File('assets/cards/announcements.json').readAsStringSync(),
  );
}

/// Stands in for the cabin server. Each connection the app opens becomes one entry in [connections].
class FakeCabin {
  final List<StreamChannelController<dynamic>> connections = [];
  final List<Uri> uris = [];
  final List<List<Map<String, dynamic>>> received = [];
  bool refuse = false;
  bool autoPong = false;

  StreamChannel<dynamic> open(Uri uri) {
    if (refuse) throw StateError('no route to host');
    uris.add(uri);
    final c = StreamChannelController<dynamic>();
    final inbox = <Map<String, dynamic>>[];
    received.add(inbox);
    c.foreign.stream.listen((m) {
      final msg = jsonDecode(m as String) as Map<String, dynamic>;
      inbox.add(msg);
      if (autoPong && msg['t'] == 'ping') c.foreign.sink.add(jsonEncode({'t': 'pong'}));
    });
    connections.add(c);
    return c.local;
  }

  StreamChannelController<dynamic> get last => connections.last;
  List<Map<String, dynamic>> get lastInbox => received.last;
  void push(Map<String, dynamic> msg, [StreamChannelController<dynamic>? to]) => (to ?? last).foreign.sink.add(jsonEncode(msg));
  void welcome([Map<String, dynamic> extra = const {}]) => push({'t': 'welcome', 'passenger': {'seat': '24C'}, 'requests': [], 'announcements': [], 'exit_check': null, 'checkin': null, 'thread': [], ...extra});
  Future<void> drop([StreamChannelController<dynamic>? c]) => (c ?? last).foreign.sink.close();
}

Map<String, dynamic> request(String id, String intent, {String status = 'new', int urgency = 1, List<Map<String, dynamic>> replies = const [], double? understood, double created = 1}) =>
    {'id': id, 'seat': '24C', 'intent': intent, 'urgency': urgency, 'via': 'tap', 'status': status, 'created': created, 'replies': replies, 'understood_at': understood};


/// A cabin session that is already connected to a [FakeCabin] (no heartbeat, so no timers are left over).
Future<(CabinSession, FakeCabin)> onlineSession(WidgetTester t, {Profile? profile}) async {
  final p = profile ?? Profile(lang: 'hi', seat: '24C');
  final cabin = FakeCabin();
  final session = CabinSession.forProfile(p, makeLink: (store) => CabinLink(store, factory: cabin.open, pingEvery: Duration.zero));
  addTearDown(session.dispose);
  session.connect('http://cabin.test:8000');
  await t.pump();
  cabin.welcome();
  await t.pump();
  return (session, cabin);
}

/// Records what the app would have played or spoken, instead of making sound.
class SoundLog {
  final clips = <String>[];
  final spoken = <String>[];
  late final Future<void> Function(String, String, String) _oldClip = playClip;
  late final Future<void> Function(String, String) _oldSpeak = speakText;

  void install() {
    playClip = (asset, text, lang) async => clips.add(asset);
    speakText = (text, locale) async => spoken.add('$locale:$text');
  }

  void restore() {
    playClip = _oldClip;
    speakText = _oldSpeak;
  }
}
