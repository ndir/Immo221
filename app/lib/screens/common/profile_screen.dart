import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../widgets.dart';
import '../home_router.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _whatsapp = TextEditingController();
  final _agency = TextEditingController();
  String _role = 'seeker';
  String _phone = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Api.instance.myProfile().then((p) {
      if (!mounted || p == null) return;
      setState(() {
        _name.text = p['display_name'] as String? ?? '';
        _whatsapp.text = p['whatsapp_phone'] as String? ?? '';
        _agency.text = p['agency_name'] as String? ?? '';
        _role = p['role'] as String? ?? 'seeker';
        _phone = p['phone'] as String? ?? '';
        _loading = false;
      });
    });
  }

  Future<void> _save() async {
    final wa = _whatsapp.text.replaceAll(RegExp(r'[^\d+]'), '');
    if (wa.isNotEmpty && !RegExp(r'^\+\d{8,15}$').hasMatch(wa)) {
      showMessage(context, 'Numéro WhatsApp au format international, par exemple +221771234567.');
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.instance.updateProfile({
        'display_name': _name.text.trim(),
        'whatsapp_phone': wa.isEmpty ? _phone : wa,
        if (_role == 'agency') 'agency_name': _agency.text.trim(),
      });
      if (mounted) showMessage(context, 'Profil enregistré.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _switchRole(String role) async {
    try {
      await Api.instance.setRole(role);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      HomeRouter.refresh.value++;
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
              Text('${roleLabels[_role]} · $_phone', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Prénom ou nom')),
              const SizedBox(height: 14),
              TextField(
                controller: _whatsapp,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Numéro WhatsApp', helperText: 'Si différent du numéro de connexion'),
              ),
              if (_role == 'agency') ...[
                const SizedBox(height: 14),
                TextField(controller: _agency, decoration: const InputDecoration(labelText: "Nom de l'agence")),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: _saving ? null : _save, child: LoadingOr(loading: _saving, child: const Text('Enregistrer'))),
              const SizedBox(height: 24),
              if (_role == 'seeker')
                OutlinedButton(onPressed: () => _switchRole('owner'), child: const Text('Je propose aussi des biens'))
              else
                OutlinedButton(onPressed: () => _switchRole('seeker'), child: const Text('Passer en mode demandeur')),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  await Api.instance.signOut();
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                },
                child: const Text('Se déconnecter'),
              ),
            ]),
    );
  }
}
