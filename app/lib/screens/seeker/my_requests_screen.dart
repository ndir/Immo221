import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Suivi des demandes : écoutes, contacts reçus, prolonger, clôturer.
class MyRequestsScreen extends StatefulWidget {
  final VoidCallback onNewRequest;
  const MyRequestsScreen({super.key, required this.onNewRequest});

  @override
  State<MyRequestsScreen> createState() => MyRequestsScreenState();
}

class MyRequestsScreenState extends State<MyRequestsScreen> {
  late Future<List<SeekerRequest>> _future = Api.instance.myRequests();

  Future<void> reload() async {
    final f = Api.instance.myRequests();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      child: FutureBuilder<List<SeekerRequest>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return ListView(children: [
              Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(snap.error!), textAlign: TextAlign.center)),
            ]);
          }
          final list = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
            Text('Mes demandes', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            if (list.isEmpty) ...[
              const Text("Vous n'avez pas encore de demande."),
              const SizedBox(height: 16),
              FilledButton(onPressed: widget.onNewRequest, child: const Text('Enregistrer ma recherche')),
            ],
            for (final r in list) ...[
              _RequestCard(key: ValueKey('${r.id}-${r.contactsCount}-${r.status}'), request: r, onChanged: reload),
              const SizedBox(height: 16),
            ],
          ]);
        },
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  final SeekerRequest request;
  final Future<void> Function() onChanged;
  const _RequestCard({super.key, required this.request, required this.onChanged});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  late final Future<List<ContactRow>> _contacts =
      widget.request.contactsCount > 0 ? Api.instance.contacts(widget.request.id) : Future.value(const <ContactRow>[]);

  SeekerRequest get r => widget.request;

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showMessage(context, done);
      await widget.onChanged();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _found(List<ContactRow> contacts) async {
    String? helped = contacts.isNotEmpty ? contacts.first.ownerId : null;
    var rating = 5;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Bravo ! Qui vous a aidé ?'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in contacts)
                RadioListTile<String?>(
                  contentPadding: EdgeInsets.zero,
                  value: c.ownerId,
                  groupValue: helped,
                  onChanged: (v) => setLocal(() => helped = v),
                  title: Text(c.ownerName),
                  subtitle: Text(c.subtitle),
                ),
              RadioListTile<String?>(
                contentPadding: EdgeInsets.zero,
                value: null,
                groupValue: helped,
                onChanged: (v) => setLocal(() => helped = v),
                title: const Text('Personne de Dëkk'),
              ),
              if (helped != null) ...[
                const SizedBox(height: 8),
                const Text('Votre note', style: TextStyle(fontWeight: FontWeight.w700)),
                Row(children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i étoile${i > 1 ? 's' : ''}',
                      onPressed: () => setLocal(() => rating = i),
                      icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: DekkColors.ochre, size: 32),
                    ),
                ]),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(() => Api.instance.close(r.id, helpedOwner: helped, rating: helped == null ? null : rating),
          'Félicitations pour votre nouveau logement !');
    }
  }

  Future<void> _report(ContactRow c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Signaler ${c.ownerName} ?'),
        content: const Text('Utilisez le signalement en cas de comportement insistant, insultant ou d\'arnaque.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Signaler')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => Api.instance.report(c.ownerId, requestId: r.id), 'Merci, notre équipe va examiner ce signalement.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = r.isActive;
    final daysLeft = r.expiresAt == null ? null : r.expiresAt!.difference(DateTime.now()).inHours / 24;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: active ? DekkColors.green : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: DefaultTextStyle(
          style: TextStyle(color: active ? Colors.white : DekkColors.ink),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (active)
                Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(color: Color(0xFF9BE0BF), shape: BoxShape.circle)),
              Text(statusLabels[r.status] ?? r.status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (active && daysLeft != null)
                Text(daysLeft < 1 ? 'expire bientôt' : 'encore ${daysLeft.ceil()} j', style: const TextStyle(fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            Text(r.summary ?? 'Demande', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.35)),
          ]),
        ),
      ),
      if (r.status == 'published' || r.status == 'expired' || r.status == 'found') ...[
        const SizedBox(height: 12),
        Row(children: [
          StatTile('${r.listenCount}', 'écoutes du vocal'),
          const SizedBox(width: 12),
          StatTile('${r.contactsCount} / ${r.maxContacts}', 'offreurs vous ont écrit'),
        ]),
      ],
      FutureBuilder<List<ContactRow>>(
        future: _contacts,
        builder: (context, snap) {
          final contacts = snap.data ?? const <ContactRow>[];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SectionLabel('Qui vous a contacté'),
              Card(
                child: Column(children: [
                  for (final c in contacts)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: DekkColors.greenTint,
                        child: Text(c.ownerName.characters.first.toUpperCase(),
                            style: const TextStyle(color: DekkColors.green, fontWeight: FontWeight.w700)),
                      ),
                      title: Text(c.ownerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${c.subtitle} · ${ago(c.createdAt)}'),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Options',
                        onSelected: (_) => _report(c),
                        itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Signaler'))],
                      ),
                    ),
                ]),
              ),
            ],
            if (active || r.status == 'expired') ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _run(() => Api.instance.extend(r.id), 'Demande prolongée de 15 jours.'),
                    child: const Text('Prolonger'),
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _run(() => Api.instance.remove(r.id), 'Demande retirée.'),
                      child: const Text('Retirer'),
                    ),
                  ),
                ],
              ]),
            ],
            if (active) ...[
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: DekkColors.ochre, foregroundColor: DekkColors.ink),
                onPressed: () => _found(contacts),
                child: const Text("J'ai trouvé mon logement"),
              ),
            ],
          ]);
        },
      ),
    ]);
  }
}
