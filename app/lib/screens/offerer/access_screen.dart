import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Accès : gratuit au lancement, forfaits annoncés pour plus tard.
class AccessScreen extends StatelessWidget {
  const AccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final free = Api.instance.freeMode;
    Widget plan(String name, String text) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(text),
            trailing: const Pill('Bientôt', background: DekkColors.lineSoft, foreground: DekkColors.muted),
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: DekkColors.green, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(free ? 'OFFRE DE LANCEMENT' : 'VOTRE ACCÈS',
              style: const TextStyle(color: DekkColors.ochreTint, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(free ? 'Tout est gratuit' : 'Forfait requis',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            free
                ? 'Contacts illimités sur WhatsApp, dans toutes les villes du Sénégal. Aucun paiement demandé.'
                : 'Les contacts sont décomptés de votre forfait.',
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      const SectionLabel('Forfaits à venir'),
      plan('Particulier', 'Quelques contacts par mois'),
      const SizedBox(height: 10),
      plan('Démarcheur Pro', 'Plus de contacts, alertes en temps réel'),
      const SizedBox(height: 10),
      plan('Agence', 'Illimité, badge vérifié, plusieurs villes'),
      const SizedBox(height: 16),
      Text('Vous serez prévenu à l\'avance. Paiement prévu par Wave et Orange Money.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
