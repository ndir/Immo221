import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../widgets.dart';
import '../seeker/fiche_screen.dart' show ZonePicker;

/// Zones d'alerte de l'offreur et réglages d'envoi.
class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key});

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  List<Subscription> _subs = [];
  List<Zone> _zones = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final zones = await Api.instance.zones();
      final subs = await Api.instance.subscriptions();
      if (mounted) {
        setState(() {
          _zones = zones;
          _subs = subs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _add() async {
    final zone = await showModalBottomSheet<Zone>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ZonePicker(zones: _zones, exclude: _subs.map((s) => s.zoneId).toSet()),
    );
    if (zone == null) return;
    try {
      await Api.instance.subscribe(zone.id);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _remove(Subscription s) async {
    try {
      await Api.instance.unsubscribe(s.id);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mes zones d'alerte")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
              const Text('Vous êtes alerté dès qu\'une demande est publiée dans ces quartiers ou villes.'),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in _subs)
                  InputChip(
                    label: Text([
                      Api.instance.zoneById(s.zoneId)?.label ?? 'Zone ${s.zoneId}',
                      if (s.transaction != null) transactionLabels[s.transaction]!,
                    ].join(' · ')),
                    onDeleted: () => _remove(s),
                    deleteButtonTooltipMessage: 'Retirer',
                  ),
                ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('Ajouter'), onPressed: _add),
              ]),
            ]),
    );
  }
}
