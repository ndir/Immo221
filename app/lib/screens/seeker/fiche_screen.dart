import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Envoi du vocal, traitement IA, puis vérification et publication de la fiche.
class FicheScreen extends StatefulWidget {
  final File audioFile;
  final Duration duration;
  const FicheScreen({super.key, required this.audioFile, required this.duration});

  @override
  State<FicheScreen> createState() => _FicheScreenState();
}

class _FicheScreenState extends State<FicheScreen> {
  final _player = AudioPlayer();
  SeekerRequest? _request;
  String? _error;
  bool _publishing = false;

  // Champs modifiables
  String? _transaction;
  String? _property;
  List<Zone> _zones = [];
  final _budget = TextEditingController();
  String _period = 'mois';
  final _bedrooms = TextEditingController();
  final _moveIn = TextEditingController();
  final _summary = TextEditingController();
  bool _urgent = false;
  int _visibility = 15;
  bool _consent = false;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _player.setFilePath(widget.audioFile.path);
    _process();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _process() async {
    setState(() => _error = null);
    try {
      final r = _request == null
          ? await Api.instance.createAndProcess(widget.audioFile, widget.duration)
          : await Api.instance.process(_request!.id);
      _fill(r);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  void _fill(SeekerRequest r) {
    setState(() {
      _request = r;
      _transaction = r.transaction;
      _property = r.property;
      _zones = r.zoneIds.map(Api.instance.zoneById).whereType<Zone>().toList();
      _budget.text = r.budgetMax == null ? '' : fcfa(r.budgetMax).replaceAll(' F', '');
      _period = r.budgetPeriod ?? ((r.transaction == 'achat' || r.transaction == 'terrain') ? 'total' : 'mois');
      _bedrooms.text = r.bedroomsMin?.toString() ?? '';
      _moveIn.text = r.moveIn ?? '';
      _summary.text = r.summary ?? '';
      _urgent = r.isUrgent;
    });
  }

  int? get _budgetValue {
    final d = _budget.text.replaceAll(RegExp(r'\D'), '');
    return d.isEmpty ? null : int.parse(d);
  }

  Future<void> _publish() async {
    final r = _request!;
    String? problem;
    if (_transaction == null) {
      problem = 'Choisissez : location, colocation, achat ou terrain.';
    } else if (_zones.isEmpty && (r.zoneFreeText ?? '').isEmpty) {
      problem = 'Ajoutez au moins un quartier ou une ville.';
    } else if (!_consent) {
      problem = "Cochez la case d'accord pour être contacté sur WhatsApp.";
    }
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _publishing = true);
    try {
      await Api.instance.publish(
        requestId: r.id,
        transaction: _transaction!,
        property: _property,
        zoneIds: _zones.map((z) => z.id).toList(),
        zoneFreeText: _zones.isEmpty ? r.zoneFreeText : null,
        budgetMin: r.budgetMin,
        budgetMax: _budgetValue,
        budgetPeriod: _budgetValue == null ? null : _period,
        bedroomsMin: int.tryParse(_bedrooms.text),
        furnished: r.furnished,
        moveIn: _moveIn.text.trim().isEmpty ? null : _moveIn.text.trim(),
        summary: _summary.text.trim().isEmpty ? null : _summary.text.trim(),
        visibilityDays: _visibility,
        isUrgent: _urgent,
        userEdited: _edited,
      );
      if (!mounted) return;
      showMessage(context, 'Votre demande est en ligne. Les offreurs vont vous écrire sur WhatsApp.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _addZone() async {
    final all = await Api.instance.zones();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Zone>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ZonePicker(zones: all, exclude: _zones.map((z) => z.id).toSet()),
    );
    if (picked != null) setState(() {
      _zones.add(picked);
      _edited = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_request == null ? '' : 'Votre fiche est prête')),
      body: _request == null ? _processing(t) : _form(t),
    );
  }

  Widget _processing(TextTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_error == null) ...[
            const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 6)),
            const SizedBox(height: 24),
            Text('On prépare votre fiche…', style: t.titleLarge),
            const SizedBox(height: 8),
            Text('Nous écoutons votre vocal. Cela prend quelques secondes.',
                textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: DekkColors.muted)),
          ] else ...[
            const Icon(Icons.error_outline_rounded, size: 48, color: DekkColors.badge),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: 20),
            FilledButton(onPressed: _process, child: const Text('Réessayer')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Refaire le vocal')),
          ],
        ]),
      ),
    );
  }

  Widget _form(TextTheme t) {
    final r = _request!;
    void edited() => _edited = true;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton.filled(
                  tooltip: playing ? 'Pause' : 'Réécouter le vocal',
                  onPressed: () async {
                    if (playing) return _player.pause();
                    if (snap.data?.processingState == ProcessingState.completed) await _player.seek(Duration.zero);
                    await _player.play();
                  },
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('« ${r.transcript ?? ''} »', style: t.bodyMedium?.copyWith(height: 1.45))),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text('Touchez un champ pour le corriger.', style: t.bodySmall),
      const SizedBox(height: 16),
      const SectionLabel('Transaction'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in transactionLabels.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: _transaction == e.key,
            onSelected: (_) => setState(() {
              _transaction = e.key;
              edited();
            }),
          ),
      ]),
      const SizedBox(height: 16),
      DropdownButtonFormField<String?>(
        value: _property,
        decoration: const InputDecoration(labelText: 'Type de bien'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Non précisé')),
          for (final e in propertyLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() {
          _property = v;
          edited();
        }),
      ),
      const SizedBox(height: 16),
      const SectionLabel('Quartiers ou villes'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final z in _zones)
          InputChip(
            label: Text(z.label),
            onDeleted: () => setState(() {
              _zones.remove(z);
              edited();
            }),
            deleteButtonTooltipMessage: 'Retirer ${z.name}',
          ),
        ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('Ajouter'), onPressed: _addZone),
      ]),
      if (_zones.isEmpty && (r.zoneFreeText ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: DekkColors.warnBg, borderRadius: BorderRadius.circular(10)),
          child: Text('Lieu non reconnu : « ${r.zoneFreeText} ». Ajoutez-le depuis la liste si possible.',
              style: const TextStyle(color: DekkColors.ochreInk, fontWeight: FontWeight.w600)),
        ),
      ],
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _budget,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d ]'))],
            decoration: const InputDecoration(labelText: 'Budget max (FCFA)'),
            onChanged: (_) => edited(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: _period,
            decoration: const InputDecoration(labelText: 'Période'),
            items: const [
              DropdownMenuItem(value: 'mois', child: Text('Par mois')),
              DropdownMenuItem(value: 'total', child: Text('Total')),
            ],
            onChanged: (v) => setState(() => _period = v ?? 'mois'),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _bedrooms,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Chambres min.'),
            onChanged: (_) => edited(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _moveIn,
            decoration: const InputDecoration(labelText: 'Emménagement'),
            onChanged: (_) => edited(),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text("C'est urgent"),
        value: _urgent,
        onChanged: (v) => setState(() {
          _urgent = v;
          edited();
        }),
      ),
      TextField(
        controller: _summary,
        maxLines: 3,
        maxLength: 160,
        decoration: const InputDecoration(labelText: 'Résumé lu par les offreurs'),
        onChanged: (_) => edited(),
      ),
      const SizedBox(height: 8),
      const SectionLabel('Visible pendant'),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 7, label: Text('7 jours')),
          ButtonSegment(value: 15, label: Text('15 jours')),
          ButtonSegment(value: 30, label: Text('30 jours')),
        ],
        selected: {_visibility},
        onSelectionChanged: (s) => setState(() => _visibility = s.first),
        showSelectedIcon: false,
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _consent,
        onChanged: (v) => setState(() => _consent = v ?? false),
        title: Text("J'accepte que jusqu'à 5 offreurs me contactent sur WhatsApp pendant $_visibility jours.",
            style: t.bodyMedium),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _publishing ? null : _publish,
        child: LoadingOr(loading: _publishing, child: const Text('Publier ma demande')),
      ),
    ]);
  }
}

/// Sélection d'un quartier ou d'une ville avec recherche.
class ZonePicker extends StatefulWidget {
  final List<Zone> zones;
  final Set<int> exclude;
  const ZonePicker({super.key, required this.zones, this.exclude = const {}});

  @override
  State<ZonePicker> createState() => _ZonePickerState();
}

class _ZonePickerState extends State<ZonePicker> {
  String _q = '';

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp('[ïî]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùû]'), 'u')
      .replaceAll('œ', 'oe')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final q = _norm(_q);
    final list = widget.zones
        .where((z) => !widget.exclude.contains(z.id))
        .where((z) => q.isEmpty || _norm(z.name).contains(q) || _norm(z.city).contains(q))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Quartier ou ville'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(list[i].name),
              subtitle: list[i].name == list[i].city ? Text(list[i].region) : Text(list[i].city),
              onTap: () => Navigator.of(context).pop(list[i]),
            ),
          ),
        ),
      ]),
    );
  }
}
