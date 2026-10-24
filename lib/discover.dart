import 'dart:convert';

import 'package:http/http.dart' as http;

/// Finds the aircraft's cabin server on the local network and joins it with the signed boarding pass.
/// The seat is never typed: it comes from the pass.

/// Where the app looks, in order. The first one that proves it is the cabin wins.
/// mDNS (.local) is not reliable on every phone, so there are fallbacks; the last is the crew QR address.
List<String> defaultCabinHosts({String? lastGood, String? fromQr, int port = 8000}) {
  final hosts = <String>[
    ?lastGood,
    'http://hashi-cabin.local:$port',
    'http://hashi.cabin:$port',
    'http://192.168.137.1:$port', // the Windows hotspot gateway used in the demo
    ?fromQr,
  ];
  final seen = <String>{};
  return [for (final h in hosts) if (seen.add(_trim(h))) _trim(h)];
}

String _trim(String url) => url.replaceAll(RegExp(r'/+$'), '');

class CabinInfo {
  final String baseUrl;
  final String flight;
  const CabinInfo(this.baseUrl, this.flight);
}

/// Pings each candidate. A host counts only if its answer says it is the HASHI cabin, so a captive portal,
/// a router page or another Wi-Fi's server that merely answers "200" is not mistaken for the aircraft.
class Discovery {
  final http.Client _http;
  final Duration timeout;
  Discovery({http.Client? client, this.timeout = const Duration(seconds: 2)}) : _http = client ?? http.Client();

  Future<CabinInfo?> find(List<String> hosts) async {
    for (final host in hosts) {
      final info = await probe(host);
      if (info != null) return info;
    }
    return null;
  }

  Future<CabinInfo?> probe(String host) async {
    final base = _trim(host);
    try {
      final r = await _http.get(Uri.parse('$base/api/ping')).timeout(timeout);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        if (j is Map && j['service'] == 'hashi-cabin') return CabinInfo(base, (j['flight'] as String?) ?? '');
        return null; // answered, but it is not the cabin
      }
      if (r.statusCode != 404) return null;
      // An older cabin server has no /api/ping yet; its health page is recognisable too.
      final h = await _http.get(Uri.parse('$base/api/health')).timeout(timeout);
      if (h.statusCode != 200) return null;
      final j = jsonDecode(h.body);
      if (j is Map && j['ok'] == true && j.containsKey('crew_connected') && j.containsKey('asr')) return CabinInfo(base, '');
    } catch (_) {
      // unreachable, timed out, or not JSON: not the cabin
    }
    return null;
  }
}

enum BoardOutcome { boarded, refused, seatTaken, unsupported, unreachable }

class BoardResult {
  final BoardOutcome outcome;
  final String? seat;
  final String? flight;
  final String? message;
  const BoardResult(this.outcome, {this.seat, this.flight, this.message});
  bool get ok => outcome == BoardOutcome.boarded;
}

/// Hands the boarding pass to the cabin. The cabin checks it and tells the crew about the seat and preferences.
Future<BoardResult> boardCabin(String cabinUrl, String grant, String deviceId, {http.Client? client, Duration timeout = const Duration(seconds: 5)}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .post(Uri.parse('${_trim(cabinUrl)}/api/board'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'grant': grant, 'device_id': deviceId}))
        .timeout(timeout);
    switch (r.statusCode) {
      case 200:
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return BoardResult(BoardOutcome.boarded, seat: j['seat'] as String?, flight: j['flight'] as String?);
      case 403:
        return BoardResult(BoardOutcome.refused, message: _detail(r.body));
      case 409:
        return BoardResult(BoardOutcome.seatTaken, message: _detail(r.body));
      case 404:
      case 405:
        return const BoardResult(BoardOutcome.unsupported);
      default:
        return BoardResult(BoardOutcome.unreachable, message: 'Cabin answered ${r.statusCode}');
    }
  } catch (_) {
    return const BoardResult(BoardOutcome.unreachable, message: 'Cabin not reachable');
  }
}

String? _detail(String body) {
  try {
    final d = jsonDecode(body)['detail'];
    return d is String ? d : null;
  } catch (_) {
    return null;
  }
}

enum CabinState { notFound, noPass, refused, seatTaken, unreachable, ready, readyWithoutPass }

class CabinConnection {
  final CabinState state;
  final String? baseUrl;
  final String? seat;
  final String? flight;
  final String? message;
  const CabinConnection(this.state, {this.baseUrl, this.seat, this.flight, this.message});
  bool get connected => state == CabinState.ready || state == CabinState.readyWithoutPass;
}

/// The whole join in one place: find the cabin, get the pass, board. [bookedSeat] is the seat read from the booking;
/// it is only used when the cabin server cannot take a pass yet (an older server), never typed by the passenger.
Future<CabinConnection> connectToCabin({
  required List<String> hosts,
  required Future<String?> Function() getGrant,
  required String deviceId,
  String? bookedSeat,
  Discovery? discovery,
  http.Client? client,
}) async {
  final cabin = await (discovery ?? Discovery(client: client)).find(hosts);
  if (cabin == null) return const CabinConnection(CabinState.notFound);

  final grant = await getGrant();
  if (grant == null) {
    // Reachable, but this phone has no valid pass (never fetched one online, or it expired).
    return CabinConnection(CabinState.noPass, baseUrl: cabin.baseUrl, flight: cabin.flight, seat: bookedSeat);
  }

  final result = await boardCabin(cabin.baseUrl, grant, deviceId, client: client);
  switch (result.outcome) {
    case BoardOutcome.boarded:
      return CabinConnection(CabinState.ready, baseUrl: cabin.baseUrl, seat: result.seat, flight: result.flight ?? cabin.flight);
    case BoardOutcome.unsupported:
      return CabinConnection(CabinState.readyWithoutPass, baseUrl: cabin.baseUrl, seat: bookedSeat, flight: cabin.flight);
    case BoardOutcome.refused:
      return CabinConnection(CabinState.refused, baseUrl: cabin.baseUrl, message: result.message);
    case BoardOutcome.seatTaken:
      return CabinConnection(CabinState.seatTaken, baseUrl: cabin.baseUrl, message: result.message);
    case BoardOutcome.unreachable:
      return CabinConnection(CabinState.unreachable, baseUrl: cabin.baseUrl, message: result.message);
  }
}
