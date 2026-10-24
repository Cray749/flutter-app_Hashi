import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'discover.dart' show localHttpClient;
import 'protocol.dart';

/// Opens the connection. Replaceable in tests.
typedef ChannelFactory = StreamChannel<dynamic> Function(Uri uri);

StreamChannel<dynamic> openWebSocket(Uri uri) => IOWebSocketChannel.connect(uri, customClient: localHttpClient(), pingInterval: null);

/// The phone's live line to the cabin server. It keeps itself connected: when the Wi-Fi blips it tries again with growing
/// pauses, and requests made meanwhile are kept and sent as soon as the line is back.
class CabinLink {
  final CabinStore store;
  final ChannelFactory _factory;
  final Duration pingEvery;
  final Duration pongWithin;
  final List<Duration> backoff;

  CabinLink(this.store, {ChannelFactory? factory, this.pingEvery = const Duration(seconds: 20), this.pongWithin = const Duration(seconds: 8), this.backoff = const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8)]})
      : _factory = factory ?? openWebSocket;

  Uri? _uri;
  Map<String, dynamic> Function()? _hello;
  StreamChannel<dynamic>? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _wanted = false;
  bool _gotWelcome = false;
  int _attempt = 0;
  Timer? _retryTimer;
  Timer? _pingTimer;
  Timer? _pongTimer;

  bool get online => store.link == LinkState.online;

  /// Turns "http://host:8000" into the passenger socket address for [seat].
  static Uri socketUri(String baseUrl, String seat) {
    final u = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), ''));
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '/ws/passenger', queryParameters: {'seat': seat});
  }

  /// Start (or restart) the connection. [hello] gives the profile to introduce this phone to the cabin with.
  void start(String baseUrl, Map<String, dynamic> Function() hello) {
    stop();
    _uri = socketUri(baseUrl, store.seat);
    _hello = hello;
    _wanted = true;
    _attempt = 0;
    _connect();
  }

  void stop() {
    _wanted = false;
    _retryTimer?.cancel();
    _closeChannel();
    store.setLink(LinkState.idle);
  }

  void _connect() {
    if (!_wanted || _uri == null) return;
    store.setLink(LinkState.connecting);
    _gotWelcome = false;
    try {
      final ch = _factory(_uri!);
      _channel = ch;
      _sub = ch.stream.listen(_onData, onError: (_) => _dropped(), onDone: _dropped, cancelOnError: true);
      _raw({'t': 'hello', ...?_hello?.call()});
    } catch (_) {
      _dropped();
    }
  }

  void _onData(dynamic data) {
    _pongTimer?.cancel(); // anything from the server proves the line is alive
    Map<String, dynamic> msg;
    try {
      msg = Map<String, dynamic>.from(jsonDecode(data as String) as Map);
    } catch (_) {
      return; // not for us
    }
    if (!_gotWelcome && msg['t'] == 'welcome') {
      _gotWelcome = true;
      _attempt = 0;
      store.apply(msg);
      store.setLink(LinkState.online);
      _flushQueue();
      _startPing();
      return;
    }
    store.apply(msg);
  }

  void _flushQueue() {
    for (final q in store.takeQueued()) {
      _raw({'t': 'request', 'intent': q.intent, 'via': q.via});
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    if (pingEvery == Duration.zero) return; // heartbeat switched off (tests)
    _pingTimer = Timer.periodic(pingEvery, (_) {
      _raw({'t': 'ping'});
      _pongTimer?.cancel();
      _pongTimer = Timer(pongWithin, _dropped); // no answer: the line is dead even if the socket says it is open
    });
  }

  void _dropped() {
    _closeChannel();
    if (!_wanted) return;
    store.setLink(LinkState.offline);
    final wait = backoff[_attempt.clamp(0, backoff.length - 1)];
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(wait, _connect);
  }

  void _closeChannel() {
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        ch.sink.close();
      } catch (_) {}
    }
  }

  bool _raw(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) return false;
    try {
      ch.sink.add(jsonEncode(msg));
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _send(Map<String, dynamic> msg) => online && _raw(msg);

  // ---- what the passenger can do ----

  /// A request from a card or the help button. Kept and sent later when the cabin cannot be reached.
  void sendRequest(String intent, {String via = 'tap'}) {
    if (!_send({'t': 'request', 'intent': intent, 'via': via})) {
      store.addQueued(QueuedRequest(intent, via));
    }
  }

  void cancelRequest(String id) => _send({'t': 'cancel', 'req_id': id});
  void understood(String requestId) => _send({'t': 'understood', 'req_id': requestId});

  void acknowledge(String announcementId) {
    _send({'t': 'ack', 'ann_id': announcementId});
    store.dismissAnnouncement(announcementId);
  }

  void answerExit(String checkId, {required bool willing, String answer = ''}) => _send({'t': 'exit_answer', 'check_id': checkId, 'willing': willing, 'answer': answer});
  void answerCheckin(String answer) => _send({'t': 'checkin_answer', 'answer': answer});
  bool say(String text) => _send({'t': 'say', 'text': text});
  void confirmSay(String id) => _send({'t': 'say_confirm', 'id': id});
  void cancelSay(String id) => _send({'t': 'say_cancel', 'id': id});

  /// Tell the cabin the passenger changed language, text size or needs.
  void updateProfile() {
    final h = _hello?.call();
    if (h != null) _send({'t': 'profile', ...h});
  }

  void dispose() {
    stop();
  }
}
