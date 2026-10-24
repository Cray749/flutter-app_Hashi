import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'decks.dart';
import 'kit.dart';
import 'languages.dart';
import 'session.dart';
import 'theme.dart';

final _tts = FlutterTts();

Future<void> speak(String text, String locale) async {
  await _tts.setLanguage(locale);
  await _tts.speak(text);
}

class DeckInfo {
  final String title;
  final String kanji;
  final String intro;
  final IconData icon;
  const DeckInfo(this.title, this.kanji, this.intro, this.icon);
}

const deckInfo = <Deck, DeckInfo>{
  Deck.before: DeckInfo('At the airport', '出発前', 'Show these at the desk, security or the gate. Tap a card to show it large.', Icons.luggage_rounded),
  Deck.flight: DeckInfo('On the flight', '機内', 'Tap what you need. The crew see it in Japanese, with your seat.', Icons.flight_rounded),
  Deck.staff: DeckInfo('Show to staff', '到着後', 'After landing: show a card to anyone who can help you.', Icons.record_voice_over_rounded),
};

/// A deck: group filter on top, then the cards.
class DeckScreen extends StatefulWidget {
  final Deck deck;
  final Profile profile;
  /// Tests can pass cards directly instead of loading the bundled file.
  final List<HashiCard>? cards;
  /// The live line to the crew; flight cards are sent through it.
  final CabinSession? session;
  const DeckScreen({super.key, required this.deck, required this.profile, this.cards, this.session});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  List<HashiCard>? cards;
  String? group; // null = all

  @override
  void initState() {
    super.initState();
    if (widget.cards != null) {
      cards = widget.cards;
    } else {
      cardsFor(widget.deck).then((c) {
        if (mounted) setState(() => cards = c);
      });
    }
  }

  Color spineFor(HashiCard c) => c.urgency >= 3 ? shu : (c.urgency == 2 ? kin : ai);

  @override
  Widget build(BuildContext context) {
    final info = deckInfo[widget.deck]!;
    final groups = groupsFor(widget.deck);
    final all = cards;
    final shown = all == null ? <HashiCard>[] : [for (final c in all) if (group == null || c.group == group) c];
    final lang = widget.profile.lang;
    return WashiPage(
      title: info.title,
      kanji: info.kanji,
      petals: false,
      children: [
        Text(info.intro, style: const TextStyle(fontSize: 16, color: sumiSoft, height: 1.35)),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('All'), selected: group == null, onSelected: (_) => setState(() => group = null))),
            for (final g in groups)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(g.icon, size: 18, color: group == g.id ? Colors.white : ai),
                  label: Text('${g.en} · ${g.ja}'),
                  selected: group == g.id,
                  onSelected: (_) => setState(() => group = g.id),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (all == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: ai))),
        for (var i = 0; i < shown.length; i++)
          Entrance(
            key: ValueKey('${widget.deck.name}-${shown[i].id}'),
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PaperCard(
                spine: spineFor(shown[i]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullCard(card: shown[i], profile: widget.profile, deck: widget.deck, session: widget.session))),
                child: Row(children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: washi, shape: BoxShape.circle, border: Border.all(color: ai.withValues(alpha: 0.15))), child: Icon(shown[i].icon, color: ai, size: 26)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (shown[i].urgency >= 3) const Padding(padding: EdgeInsets.only(bottom: 2), child: Text('URGENT · 緊急', style: TextStyle(color: shu, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1))),
                      Text(shown[i].ja, style: const TextStyle(fontFamily: serifFont, fontSize: 20, fontWeight: FontWeight.w800, color: aiDeep, height: 1.25)),
                      const SizedBox(height: 3),
                      Text(shown[i].labels[lang] != null && lang != 'en' && lang != 'ja' ? shown[i].labels[lang]! : shown[i].en, style: const TextStyle(fontSize: 15, color: sumiSoft, height: 1.3)),
                    ]),
                  ),
                  const Icon(Icons.open_in_full_rounded, color: sumiSoft, size: 20),
                ]),
              ),
            ),
          ),
        if (all != null && shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No cards in this group.')),
      ],
    );
  }
}

/// The card full screen: Japanese big for the person you are showing, a button to flip it to your own language,
/// a spoken version, and (flight deck) a button that sends it to the crew.
class FullCard extends StatefulWidget {
  final HashiCard card;
  final Profile profile;
  final Deck deck;
  final CabinSession? session;
  const FullCard({super.key, required this.card, required this.profile, required this.deck, this.session});

  @override
  State<FullCard> createState() => _FullCardState();
}

class _FullCardState extends State<FullCard> {
  String? mine;
  bool flipped = false;
  String? sendResult;
  bool sendOk = false;

  Lang get lang => langByCode(widget.profile.lang);

  @override
  void initState() {
    super.initState();
    final ready = widget.card.labels[lang.code];
    if (ready != null) {
      mine = ready;
    } else if (lang.ml != null && lang.code != 'en') {
      Kit.translate(widget.card.en, TranslateLanguage.english, lang.ml!).then((v) {
        if (mounted) setState(() => mine = v);
      });
    }
  }

  /// Sends the card to the crew over the live line. With the line down the request is kept and goes out when it is back.
  void send() {
    final session = widget.session;
    if (session == null || widget.profile.seat.isEmpty) {
      setState(() { sendOk = false; sendResult = 'Join the cabin first, so the crew know your seat.'; });
      return;
    }
    final online = session.link.online;
    session.link.sendRequest(widget.card.id);
    setState(() {
      sendOk = true;
      sendResult = online ? 'Sent to the crew · 乗務員に送りました' : 'Saved. It will be sent as soon as you are connected.';
    });
  }

  Widget face({required bool front}) {
    final c = widget.card;
    final big = front ? c.ja : (mine ?? c.en);
    return Container(
      key: ValueKey(front),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [ai, aiDeep]),
        border: Border.all(color: kin, width: 2.2),
        boxShadow: [BoxShadow(color: aiDeep.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(c.icon, color: kin, size: 46),
        const SizedBox(height: 18),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(big, textAlign: TextAlign.center, style: TextStyle(fontFamily: front ? serifFont : null, color: Colors.white, fontSize: front ? 40 : 32, fontWeight: FontWeight.w800, height: 1.3)),
          ),
        ),
        const SizedBox(height: 16),
        Text(front ? c.en : c.ja, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD5DBF0), fontSize: 19, height: 1.3)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canFlip = mine != null && lang.code != 'en' && lang.code != 'ja';
    final isFlight = widget.deck == Deck.flight;
    return Scaffold(
      backgroundColor: aiDeep,
      appBar: AppBar(backgroundColor: aiDeep, foregroundColor: Colors.white, leading: const BackButton(), title: Text(deckInfo[widget.deck]!.title, style: const TextStyle(color: Colors.white))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(children: [
            Expanded(child: FlipCard(flipped: flipped, front: face(front: true), back: face(front: false))),
            const SizedBox(height: 16),
            if (sendResult != null)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(sendOk ? Icons.check_circle : Icons.error_outline, color: sendOk ? const Color(0xFF9BD08F) : const Color(0xFFFFB4A5)), const SizedBox(width: 8), Flexible(child: Text(sendResult!, style: const TextStyle(color: Colors.white, fontSize: 16)))])),
            if (isFlight)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: shuBright, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58)),
                onPressed: send,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send to crew · 乗務員に送る'),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kin, foregroundColor: aiDeep, minimumSize: const Size.fromHeight(58)),
                  onPressed: () => speak(widget.card.ja, 'ja-JP'),
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('Play · 音声'),
                ),
              ),
              if (canFlip) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70, width: 1.4), minimumSize: const Size.fromHeight(58)),
                    onPressed: () => setState(() => flipped = !flipped),
                    icon: const Icon(Icons.flip_rounded),
                    label: Text(flipped ? 'Japanese' : lang.name),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Turns over like a paper card: the first half rotates the front away, the second half brings the back in.
class FlipCard extends StatelessWidget {
  final bool flipped;
  final Widget front;
  final Widget back;
  const FlipCard({super.key, required this.flipped, required this.front, required this.back});

  @override
  Widget build(BuildContext context) {
    final duration = motionAllowed(context) ? const Duration(milliseconds: 520) : Duration.zero;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: flipped ? 1 : 0),
      duration: duration,
      curve: Curves.easeInOutCubic,
      builder: (_, t, _) {
        final showBack = t > 0.5;
        final angle = t * math.pi;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(showBack ? angle - math.pi : angle),
          child: showBack ? back : front,
        );
      },
    );
  }
}
