import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/api.dart';
import '../services/push.dart';
import 'offerer/detail_screen.dart';
import 'offerer/offerer_home.dart';
import 'seeker/seeker_home.dart';
import 'welcome_screen.dart';

/// Choisit l'écran d'accueil selon la session et le rôle de l'utilisateur.
class HomeRouter extends StatefulWidget {
  const HomeRouter({super.key});

  /// Force le rechargement du profil (après un changement de rôle).
  static final refresh = ValueNotifier<int>(0);

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  late final StreamSubscription<AuthState> _authSub;
  Future<Map<String, dynamic>?>? _profile;

  @override
  void initState() {
    super.initState();
    _load();
    _authSub = Api.instance.sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.signedOut) _load();
    });
    HomeRouter.refresh.addListener(_load);
    Push.instance.onOpen = _openFromPush;
  }

  void _load() {
    setState(() {
      _profile = Api.instance.uid == null ? Future.value(null) : _prepare();
    });
  }

  Future<Map<String, dynamic>?> _prepare() async {
    await Future.wait([Api.instance.zones(), Api.instance.loadSettings()]);
    final p = await Api.instance.myProfile();
    unawaited(Push.instance.registerForUser());
    return p;
  }

  void _openFromPush(String type, String? requestId) {
    final nav = navigatorKey.currentState;
    if (nav == null || requestId == null) return;
    if (type == 'new_request') {
      nav.push(MaterialPageRoute(builder: (_) => DetailScreen(requestId: requestId)));
    }
    // Les autres types ouvrent l'app sur son écran d'accueil (« Ma demande » ou « Alertes »).
  }

  @override
  void dispose() {
    _authSub.cancel();
    HomeRouter.refresh.removeListener(_load);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profile,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(friendlyError(snap.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
                ]),
              ),
            ),
          );
        }
        final profile = snap.data;
        if (profile == null) return const WelcomeScreen();
        final role = profile['role'] as String? ?? 'seeker';
        return role == 'seeker' ? SeekerHome(profile: profile) : OffererHome(profile: profile);
      },
    );
  }
}
