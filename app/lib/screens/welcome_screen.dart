import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Watermarked(
        top: 0.5,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 300,
            child: Image.asset(
              'assets/accueil.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0.1, -0.6),
              semanticLabel: 'Le monument de la Renaissance africaine à Dakar',
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Dëkk',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: DekkColors.green, letterSpacing: -0.5)),
                    Pill('100 % gratuit au lancement'),
                  ]),
                  const SizedBox(height: 18),
                  Text('Trouvez un logement en parlant, partout au Sénégal', style: t.headlineMedium),
                  const SizedBox(height: 12),
                  Text(
                    'Dakar, Thiès, Mbour, Saint-Louis, Touba, Ziguinchor… Laissez un vocal, '
                    'les propriétaires et agences vous écrivent sur WhatsApp.',
                    style: t.bodyLarge?.copyWith(color: DekkColors.muted, height: 1.5),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const LoginScreen(intent: LoginIntent.seek))),
                    child: const Text('Je cherche un logement'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: DekkColors.ink, width: 1.5),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const LoginScreen(intent: LoginIntent.offer))),
                    child: const Text('Je propose un bien'),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
