import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_router.dart';

enum LoginIntent { seek, offer }

/// Connexion par numéro de téléphone + code SMS. Pour un offreur, choix du profil ensuite.
class LoginScreen extends StatefulWidget {
  final LoginIntent intent;
  const LoginScreen({super.key, required this.intent});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _agency = TextEditingController();
  String? _sentTo;
  bool _busy = false;
  bool _pickRole = false;
  String _role = 'broker';

  static String? normalize(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00221')) d = d.substring(5);
    if (d.startsWith('221') && d.length == 12) d = d.substring(3);
    return RegExp(r'^7[05678]\d{7}$').hasMatch(d) ? '+221$d' : null;
  }

  Future<void> _send() async {
    final phone = normalize(_phone.text);
    if (phone == null) {
      showMessage(context, 'Entrez un numéro sénégalais à 9 chiffres, par exemple 77 123 45 67.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.instance.sendCode(phone);
      setState(() => _sentTo = phone);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6) {
      showMessage(context, 'Le code comporte 6 chiffres.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.instance.verifyCode(_sentTo!, _code.text.trim(), name: _name.text);
      final profile = await Api.instance.myProfile();
      if (!mounted) return;
      if (widget.intent == LoginIntent.offer && (profile?['role'] ?? 'seeker') == 'seeker') {
        setState(() => _pickRole = true);
      } else {
        Navigator.of(context).popUntil((r) => r.isFirst);
        HomeRouter.refresh.value++;
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRole() async {
    setState(() => _busy = true);
    try {
      await Api.instance.setRole(_role);
      if (_role == 'agency' && _agency.text.trim().isNotEmpty) {
        await Api.instance.updateProfile({'agency_name': _agency.text.trim()});
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      HomeRouter.refresh.value++;
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final offer = widget.intent == LoginIntent.offer;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          if (_pickRole) ..._roleStep(t) else ...[
            Text(offer ? 'Votre compte offreur' : 'Votre numéro WhatsApp', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text(
              offer
                  ? 'Recevez les demandes de vos zones et contactez les demandeurs sur WhatsApp.'
                  : "C'est là que les offreurs vous écriront. Nous le vérifions par SMS.",
              style: t.bodyLarge?.copyWith(color: DekkColors.muted),
            ),
            const SizedBox(height: 24),
            if (_sentTo == null) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Votre prénom (ou nom)'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                decoration: const InputDecoration(labelText: 'Numéro WhatsApp', prefixText: '+221 '),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: LoadingOr(loading: _busy, child: const Text('Recevoir le code')),
              ),
            ] else ...[
              Text('Code envoyé au $_sentTo', style: t.bodyMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofillHints: const [AutofillHints.oneTimeCode],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 8),
                decoration: const InputDecoration(labelText: 'Code reçu par SMS', counterText: ''),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _verify,
                child: LoadingOr(loading: _busy, child: const Text('Valider')),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => setState(() => _sentTo = null), child: const Text('Changer de numéro')),
            ],
          ],
        ]),
      ),
    );
  }

  List<Widget> _roleStep(TextTheme t) {
    Widget option(String value, String title, String subtitle) => Card(
          child: RadioListTile<String>(
            value: value,
            groupValue: _role,
            onChanged: (v) => setState(() => _role = v!),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle),
          ),
        );
    return [
      Text('Vous êtes…', style: t.headlineMedium),
      const SizedBox(height: 16),
      option('owner', 'Propriétaire', 'Je loue ou vends mon propre bien'),
      const SizedBox(height: 8),
      option('broker', 'Démarcheur', "J'accompagne des clients vers des biens"),
      const SizedBox(height: 8),
      option('agency', 'Agence', 'Agence immobilière'),
      if (_role == 'agency') ...[
        const SizedBox(height: 12),
        TextField(controller: _agency, decoration: const InputDecoration(labelText: "Nom de l'agence")),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _busy ? null : _saveRole,
        child: LoadingOr(loading: _busy, child: const Text('Continuer')),
      ),
    ];
  }
}
