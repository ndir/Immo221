import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../config.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'fiche_screen.dart';

enum _RecState { idle, recording, review }

/// Écran principal du demandeur : enregistrer son besoin en vocal.
class RecordScreen extends StatefulWidget {
  final VoidCallback onPublished;
  const RecordScreen({super.key, required this.onPublished});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  _RecState _state = _RecState.idle;
  String? _path;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _levels = List.filled(28, 0.1);

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) showMessage(context, "Autorisez l'accès au micro dans les réglages du téléphone.");
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    _elapsed = Duration.zero;
    _levels.fillRange(0, _levels.length, 0.1);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      setState(() => _elapsed += const Duration(milliseconds: 250));
      if (_elapsed >= Config.maxRecording) _stop();
    });
    _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      // dBFS : -60 (silence) … 0 (fort)
      final level = ((a.current + 60) / 60).clamp(0.05, 1.0);
      setState(() {
        _levels.removeAt(0);
        _levels.add(level);
      });
    });
    setState(() => _state = _RecState.recording);
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    final path = await _recorder.stop();
    if (path == null || _elapsed < const Duration(seconds: 2)) {
      setState(() => _state = _RecState.idle);
      if (mounted) showMessage(context, 'Vocal trop court. Parlez quelques secondes.');
      return;
    }
    _path = path;
    await _player.setFilePath(path);
    setState(() => _state = _RecState.review);
  }

  void _restart() {
    _player.stop();
    if (_path != null) File(_path!).delete().ignore();
    setState(() {
      _path = null;
      _state = _RecState.idle;
    });
  }

  Future<void> _send() async {
    await _player.stop();
    if (!mounted) return;
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FicheScreen(audioFile: File(_path!), duration: _elapsed)),
    );
    if (published == true) {
      _restart();
      widget.onPublished();
    }
  }

  String get _clock => '${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
      Text('Dites-nous ce que vous cherchez', style: t.headlineMedium),
      const SizedBox(height: 8),
      Text('Parlez en français ou en wolof. On prépare la fiche pour vous.',
          style: t.bodyLarge?.copyWith(color: DekkColors.muted)),
      const SizedBox(height: 20),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.3,
        children: const [
          _Hint('Quoi ?', 'Appartement, chambre, terrain…'),
          _Hint('Où ?', 'Ville et quartier'),
          _Hint('Combien ?', 'Par mois ou total'),
          _Hint('Pour quand ?', 'Tout de suite, le mois prochain…'),
        ],
      ),
      const SizedBox(height: 28),
      SizedBox(
        height: 56,
        child: _state == _RecState.recording
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final l in _levels)
                    Container(
                      width: 4,
                      height: 6 + 50 * l,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: DekkColors.green, borderRadius: BorderRadius.circular(2)),
                    ),
                ],
              )
            : null,
      ),
      const SizedBox(height: 8),
      if (_state != _RecState.review)
        Center(
          child: Semantics(
            button: true,
            label: _state == _RecState.recording ? "Arrêter l'enregistrement" : 'Enregistrer votre vocal',
            child: GestureDetector(
              onTap: _state == _RecState.recording ? _stop : _start,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DekkColors.ochre,
                  border: Border.all(color: DekkColors.ochreTint, width: 10),
                ),
                child: Center(
                  child: _state == _RecState.recording
                      ? Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(color: DekkColors.ink, borderRadius: BorderRadius.circular(8)))
                      : const Icon(Icons.mic_rounded, size: 52, color: DekkColors.ink),
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      Center(
        child: Text(
          switch (_state) {
            _RecState.idle => 'Appuyez pour parler · 1 min 30 max',
            _RecState.recording => 'Enregistrement · $_clock / 1:30',
            _RecState.review => 'Votre vocal · $_clock',
          },
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: DekkColors.muted),
        ),
      ),
      if (_state == _RecState.review) ...[
        const SizedBox(height: 12),
        Card(
          child: StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snap) {
              final playing = snap.data?.playing ?? false;
              final done = snap.data?.processingState == ProcessingState.completed;
              return ListTile(
                leading: IconButton.filled(
                  tooltip: playing ? 'Pause' : 'Réécouter',
                  onPressed: () async {
                    if (playing) {
                      await _player.pause();
                    } else {
                      if (done) await _player.seek(Duration.zero);
                      await _player.play();
                    }
                  },
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                title: const Text('Réécouter mon vocal', style: TextStyle(fontWeight: FontWeight.w700)),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _restart, child: const Text('Recommencer'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: _send, child: const Text('Envoyer'))),
        ]),
      ],
    ]);
  }
}

class _Hint extends StatelessWidget {
  final String title;
  final String text;
  const _Hint(this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(text, style: const TextStyle(fontSize: 12.5, color: DekkColors.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
