import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../common/notifications_screen.dart';
import '../common/profile_screen.dart';
import 'access_screen.dart';
import 'contacts_screen.dart';
import 'feed_screen.dart';

class OffererHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const OffererHome({super.key, required this.profile});

  @override
  State<OffererHome> createState() => _OffererHomeState();
}

class _OffererHomeState extends State<OffererHome> {
  int _tab = 0;
  late final Stream<List<AppNotification>> _notifications = Api.instance.notificationsStream();
  final _contactsKey = GlobalKey<ContactsScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(const ['Demandes', 'Mes contacts', 'Mon accès'][_tab]),
        actions: [
          StreamBuilder<List<AppNotification>>(
            stream: _notifications,
            builder: (context, snap) {
              final unread = (snap.data ?? const []).where((n) => n.readAt == null).length;
              return BellButton(
                unread: unread,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const NotificationsScreen(isOfferer: true))),
              );
            },
          ),
          if (Api.instance.freeMode)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _tab = 2),
                child: const Pill('Accès gratuit'),
              ),
            ),
          IconButton(
            tooltip: 'Profil',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: Watermarked(
        top: 0.3,
        child: IndexedStack(index: _tab, children: [
          FeedScreen(onContacted: () => _contactsKey.currentState?.reload()),
          ContactsScreen(key: _contactsKey),
          const AccessScreen(),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _contactsKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Demandes'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Mes contacts'),
          NavigationDestination(icon: Icon(Icons.credit_card_outlined), label: 'Accès'),
        ],
      ),
    );
  }
}

/// Couleur de l'étiquette d'une demande.
Color tagColor(FeedItem f) {
  if (f.isUrgent) return DekkColors.urgent;
  if (f.transaction == 'achat' || f.transaction == 'terrain') return const Color(0xFF33407A);
  return DekkColors.green;
}
