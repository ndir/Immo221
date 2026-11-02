import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// « Mes contacts » : les demandes débloquées par l'offreur et leur suivi.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => ContactsScreenState();
}

class ContactsScreenState extends State<ContactsScreen> {
  late Future<List<UnlockRow>> _future = Api.instance.myUnlocks();

  Future<void> reload() async {
    final f = Api.instance.myUnlocks();
    setState(() => _future = f);
    await f;
  }

  static const _outcomes = {'en_cours': 'En cours', 'conclu': 'Conclu', 'sans_suite': 'Sans suite'};

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      child: FutureBuilder<List<UnlockRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(snap.error!)))]);
          final list = snap.data!;
          if (list.isEmpty) {
            return ListView(children: const [
              Padding(
                padding: EdgeInsets.all(32),
                child: Text('Les demandeurs que vous contactez apparaîtront ici.', textAlign: TextAlign.center),
              ),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final u = list[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text('${u.seekerFirstName ?? 'Demandeur'} · ${u.zoneLabel}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Text(ago(u.createdAt), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    const SizedBox(height: 6),
                    Text(u.summary ?? '', style: const TextStyle(height: 1.35)),
                    const SizedBox(height: 10),
                    Row(children: [
                      DropdownButton<String>(
                        value: u.outcome,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final e in _outcomes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          try {
                            await Api.instance.setOutcome(u.requestId, v);
                            reload();
                          } catch (e) {
                            if (context.mounted) showMessage(context, friendlyError(e));
                          }
                        },
                      ),
                      const Spacer(),
                      if (u.seekerWhatsapp != null)
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse('https://wa.me/${u.seekerWhatsapp!.replaceAll(RegExp(r'\D'), '')}'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.chat_rounded, color: DekkColors.green),
                          label: const Text('WhatsApp'),
                        ),
                    ]),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
