import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'offerer_home.dart';

/// Détail d'une demande : écoute du vocal, fiche, contact WhatsApp.
class DetailScreen extends StatefulWidget {
  final String requestId;
  final FeedItem? initial;
  const DetailScreen({super.key, required this.requestId, this.initial});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _player = AudioPlayer();
  FeedItem? _item;
  bool _loading = true;
  bool _audioReady = false;
  bool _listened = false;
  bool _contacting = false;
  bool _contacted = false;

  @override
  void initState() {
    super.initState();
    _item = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final item = await Api.instance.feedItem(widget.requestId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
      if (item != null) {
        final url = await Api.instance.signedAudioUrl(item.audioPath);
        await _player.setUrl(url);
        if (mounted) setState(() => _audioReady = true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showMessage(context, friendlyError(e));
    }
  }

  Future<void> _togglePlay(PlayerState? s) async {
    if (s?.playing ?? false) return _player.pause();
    if (s?.processingState == ProcessingState.completed) await _player.seek(Duration.zero);
    if (!_listened) {
      _listened = true;
      Api.instance.registerListen(widget.requestId).ignore();
    }
    await _player.play();
  }

  Future<void> _contact() async {
    setState(() => _contacting = true);
    try {
      final res = await Api.instance.unlock(widget.requestId);
      final phone = (res['whatsapp_phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
      final message = res['message'] as String? ?? '';
      _contacted = true;
      final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showMessage(context, "WhatsApp n'a pas pu s'ouvrir. Numéro : +$phone");
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _item;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_contacted);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.of(context).pop(_contacted)),
          title: Text(f == null ? '' : 'Publiée ${ago(f.publishedAt)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        body: f == null
            ? Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text("Cette demande n'est plus disponible : elle a été clôturée, a expiré ou a reçu tous ses contacts.",
                            textAlign: TextAlign.center),
                      ),
              )
            : _body(f),
        bottomNavigationBar: f == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FilledButton.icon(
                      onPressed: _contacting ? null : _contact,
                      icon: const Icon(Icons.chat_rounded),
                      label: LoadingOr(
                        loading: _contacting,
                        child: Text(f.alreadyUnlocked || _contacted ? 'Rouvrir la conversation WhatsApp' : 'Contacter sur WhatsApp'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Api.instance.freeMode
                          ? 'Gratuit pendant le lancement. Un message pré-rempli citant la demande s\'ouvrira.'
                          : 'Un contact sera décompté de votre forfait.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ]),
                ),
              ),
      ),
    );
  }

  Widget _body(FeedItem f) {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
      Text(f.tag.toUpperCase(),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: tagColor(f))),
      const SizedBox(height: 6),
      Text(f.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.25)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: DekkColors.ink, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snap) {
              final playing = snap.data?.playing ?? false;
              return Row(children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: DekkColors.ochre, foregroundColor: DekkColors.ink),
                  tooltip: playing ? 'Pause' : 'Écouter le vocal',
                  onPressed: _audioReady ? () => _togglePlay(snap.data) : null,
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, pos) {
                      final total = _player.duration?.inMilliseconds ?? 1;
                      final v = ((pos.data?.inMilliseconds ?? 0) / total).clamp(0.0, 1.0);
                      return LinearProgressIndicator(
                        value: v,
                        color: DekkColors.ochre,
                        backgroundColor: Colors.white24,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Text(f.duration, style: const TextStyle(color: Color(0xFFC9D3CE), fontWeight: FontWeight.w600)),
              ]);
            },
          ),
          if ((f.transcript ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('« ${f.transcript} »', style: const TextStyle(color: Color(0xFFE2E8E5), height: 1.5)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
        children: [
          _Fact('Budget max', f.budgetMax == null ? 'Non précisé' : fcfa(f.budgetMax, period: f.budgetPeriod)),
          _Fact('Bien', [
            propertyLabels[f.property] ?? 'Non précisé',
            if (f.bedroomsMin != null) '${f.bedroomsMin} ch. min',
          ].join(' · ')),
          _Fact('Quartiers', f.place),
          _Fact('Emménagement', f.moveIn ?? 'Non précisé'),
        ],
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: DekkColors.greenTint,
            child: Text((f.seekerFirstName ?? '?').characters.first.toUpperCase(),
                style: const TextStyle(color: DekkColors.green, fontWeight: FontWeight.w700)),
          ),
          title: Text(f.seekerFirstName ?? 'Demandeur', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('+221 •• ••• •• ••'),
          trailing: Text('${f.contactsCount} / ${f.maxContacts} contacts',
              style: const TextStyle(fontWeight: FontWeight.w700, color: DekkColors.muted, fontSize: 12)),
        ),
      ),
    ]);
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
