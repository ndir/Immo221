import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../common/notifications_screen.dart';
import '../common/profile_screen.dart';
import 'my_requests_screen.dart';
import 'record_screen.dart';

class SeekerHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const SeekerHome({super.key, required this.profile});

  @override
  State<SeekerHome> createState() => _SeekerHomeState();
}

class _SeekerHomeState extends State<SeekerHome> {
  int _tab = 0;
  final _requestsKey = GlobalKey<MyRequestsScreenState>();
  late final Stream<List<AppNotification>> _notifications = Api.instance.notificationsStream();

  void _onPublished() {
    setState(() => _tab = 1);
    _requestsKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.profile['display_name'] as String? ?? '').trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dëkk', style: TextStyle(color: DekkColors.green, fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          StreamBuilder<List<AppNotification>>(
            stream: _notifications,
            builder: (context, snap) {
              final unread = (snap.data ?? const []).where((n) => n.readAt == null).length;
              return BellButton(
                unread: unread,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const NotificationsScreen(isOfferer: false))),
              );
            },
          ),
          IconButton(
            tooltip: 'Profil',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: DekkColors.greenTint,
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(color: DekkColors.green, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Watermarked(
        child: IndexedStack(index: _tab, children: [
          RecordScreen(onPublished: _onPublished),
          MyRequestsScreen(key: _requestsKey, onNewRequest: () => setState(() => _tab = 0)),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _requestsKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.mic_none_rounded), selectedIcon: Icon(Icons.mic_rounded), label: 'Demander'),
          NavigationDestination(icon: Icon(Icons.list_alt_rounded), label: 'Mes demandes'),
        ],
      ),
    );
  }
}
