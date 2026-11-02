import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../offerer/detail_screen.dart';
import '../offerer/zones_screen.dart';

/// Centre de notifications (demandeur ou offreur) et réglages d'envoi.
class NotificationsScreen extends StatefulWidget {
  final bool isOfferer;
  const NotificationsScreen({super.key, required this.isOfferer});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Stream<List<AppNotification>> _stream = Api.instance.notificationsStream();
  Map<String, dynamic>? _settings;
  Map<String, bool> _prefs = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final s = await Api.instance.userSettings();
      final p = await Api.instance.notificationPrefs();
      if (mounted) {
        setState(() {
          _settings = s;
          _prefs = p;
        });
      }
    } catch (_) {/* réglages facultatifs */}
  }

  Future<void> _setSetting(String key, bool value) async {
    setState(() => _settings = {...?_settings, key: value});
    try {
      await Api.instance.updateUserSettings({key: value});
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _setPref(String type, bool value) async {
    setState(() => _prefs = {..._prefs, type: value});
    try {
      await Api.instance.setNotificationPref(type, value);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _open(AppNotification n) async {
    if (n.readAt == null) Api.instance.markRead([n.id]).ignore();
    if (widget.isOfferer && n.type == 'new_request' && n.requestId != null) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen(requestId: n.requestId!)));
    } else if (!widget.isOfferer) {
      Navigator.of(context).pop(); // retour à « Mes demandes »
    }
  }

  static IconData _icon(String type) => switch (type) {
        'owner_contacted' => Icons.chat_rounded,
        'new_request' => Icons.mic_rounded,
        'request_expiring' => Icons.timer_outlined,
        'listen_digest' => Icons.graphic_eq_rounded,
        'found_thanks' => Icons.star_rounded,
        'request_published' => Icons.check_rounded,
        _ => Icons.notifications_none_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOfferer ? 'Alertes' : 'Notifications'),
        actions: [
          TextButton(onPressed: () => Api.instance.markRead(), child: const Text('Tout marquer lu')),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _stream,
        builder: (context, snap) {
          final list = snap.data ?? const <AppNotification>[];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            if (snap.connectionState == ConnectionState.waiting && list.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (snap.hasData && list.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Text('Aucune notification pour le moment.', textAlign: TextAlign.center)),
            for (final n in list) ...[
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: n.readAt == null
                      ? BorderSide(color: n.type == 'new_request' && n.title.startsWith('Urgent') ? DekkColors.urgent : DekkColors.green, width: 2)
                      : BorderSide.none,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: n.readAt == null ? DekkColors.green : DekkColors.lineSoft,
                    foregroundColor: n.readAt == null ? Colors.white : DekkColors.muted,
                    child: Icon(_icon(n.type), size: 20),
                  ),
                  title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
                  subtitle: Text('${n.body}\n${ago(n.createdAt)}'),
                  isThreeLine: true,
                  onTap: () => _open(n),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
            if (_settings != null) ..._settingsSection(),
          ]);
        },
      ),
    );
  }

  List<Widget> _settingsSection() {
    final s = _settings!;
    bool pref(String t) => _prefs[t] ?? true;
    final tiles = widget.isOfferer
        ? <Widget>[
            ListTile(
              title: const Text("Mes zones d'alerte"),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ZonesScreen())),
            ),
            SwitchListTile(
              title: const Text('Alerte immédiate'),
              subtitle: const Text('Sinon, un résumé le matin et le soir'),
              value: s['instant_alerts'] as bool? ?? true,
              onChanged: (v) => _setSetting('instant_alerts', v),
            ),
            SwitchListTile(
              title: const Text('Silence de 22 h à 7 h'),
              value: s['quiet_hours'] as bool? ?? true,
              onChanged: (v) => _setSetting('quiet_hours', v),
            ),
            SwitchListTile(
              title: const Text('Nouvelles demandes'),
              value: pref('new_request'),
              onChanged: (v) => _setPref('new_request', v),
            ),
          ]
        : <Widget>[
            SwitchListTile(
              title: const Text('Un offreur me contacte'),
              value: pref('owner_contacted'),
              onChanged: (v) => _setPref('owner_contacted', v),
            ),
            SwitchListTile(
              title: const Text('Ma demande va expirer'),
              value: pref('request_expiring'),
              onChanged: (v) => _setPref('request_expiring', v),
            ),
            SwitchListTile(
              title: const Text('Résumé des écoutes (1 fois par jour)'),
              value: s['daily_listen_digest'] as bool? ?? false,
              onChanged: (v) => _setSetting('daily_listen_digest', v),
            ),
            SwitchListTile(
              title: const Text('Silence de 22 h à 7 h'),
              value: s['quiet_hours'] as bool? ?? true,
              onChanged: (v) => _setSetting('quiet_hours', v),
            ),
          ];
    return [
      SectionLabel(widget.isOfferer ? 'Réglages des alertes' : 'Me prévenir quand'),
      Card(child: Column(children: tiles)),
    ];
  }
}
