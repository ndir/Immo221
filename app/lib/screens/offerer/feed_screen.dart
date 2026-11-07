import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import 'detail_screen.dart';
import 'offerer_home.dart';
import 'zones_screen.dart';

/// Fil des demandes en cours, filtrable par zones suivies et type de transaction.
class FeedScreen extends StatefulWidget {
  final VoidCallback onContacted;
  const FeedScreen({super.key, required this.onContacted});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<(List<FeedItem>, List<Subscription>)> _future = _load();
  bool _onlyMyZones = true;
  String? _transaction;

  Future<(List<FeedItem>, List<Subscription>)> _load() async {
    final results = await Future.wait([Api.instance.feed(), Api.instance.subscriptions()]);
    return (results[0] as List<FeedItem>, results[1] as List<Subscription>);
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  Future<void> _open(FeedItem item) async {
    final contacted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DetailScreen(requestId: item.id, initial: item)),
    );
    if (contacted == true) widget.onContacted();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<FeedItem>, List<Subscription>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(friendlyError(snap.error!)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Réessayer')),
            ]),
          );
        }
        final (items, subs) = snap.data!;
        final myZones = subs.map((s) => s.zoneId).toSet();
        final visible = items.where((f) {
          if (_onlyMyZones && myZones.isNotEmpty && !f.zoneIds.any(myZones.contains)) return false;
          if (_transaction != null && f.transaction != _transaction) return false;
          return true;
        }).toList();

        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                FilterChip(
                  label: Text(myZones.isEmpty ? 'Choisir mes zones' : 'Mes zones · ${myZones.length}'),
                  selected: _onlyMyZones && myZones.isNotEmpty,
                  onSelected: (v) async {
                    if (myZones.isEmpty) {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ZonesScreen()));
                      _reload();
                    } else {
                      setState(() => _onlyMyZones = v);
                    }
                  },
                ),
                for (final e in transactionLabels.entries) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(e.value),
                    selected: _transaction == e.key,
                    onSelected: (v) => setState(() => _transaction = v ? e.key : null),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            if (myZones.isEmpty)
              Card(
                color: DekkColors.warnBg,
                child: ListTile(
                  title: const Text("Choisissez vos zones pour recevoir des alertes", style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ZonesScreen()));
                    _reload();
                  },
                ),
              ),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Text('Aucune demande pour ces critères pour le moment.\nTirez vers le bas pour actualiser.',
                    textAlign: TextAlign.center),
              ),
            for (final f in visible) ...[
              const SizedBox(height: 12),
              _FeedCard(item: f, onTap: () => _open(f)),
            ],
          ]),
        );
      },
    );
  }
}

class _FeedCard extends StatelessWidget {
  final FeedItem item;
  final VoidCallback onTap;
  const _FeedCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final f = item;
    final left = f.maxContacts - f.contactsCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(f.tag.toUpperCase(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: tagColor(f))),
              ),
              Text(ago(f.publishedAt), style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 8),
            Text(f.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35)),
            const SizedBox(height: 10),
            Row(children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: DekkColors.greenTint,
                child: Icon(Icons.play_arrow_rounded, size: 18, color: DekkColors.green),
              ),
              const SizedBox(width: 8),
              Text(f.duration, style: const TextStyle(fontWeight: FontWeight.w600, color: DekkColors.muted)),
              const Spacer(),
              Text(fcfa(f.budgetMax, period: f.budgetPeriod), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text(
              f.alreadyUnlocked
                  ? 'Vous avez déjà contacté cette personne'
                  : f.contactsCount == 0
                      ? 'Aucun contact pour l\'instant'
                      : '${f.contactsCount} offreur${f.contactsCount > 1 ? 's' : ''} sur ${f.maxContacts} · encore $left place${left > 1 ? 's' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      ),
    );
  }
}
