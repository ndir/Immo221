import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';

/// Notifications push (Firebase Cloud Messaging).
/// Facultatif : sans fichier google-services.json, l'app fonctionne avec le centre
/// de notifications intégré uniquement.
class Push {
  Push._();
  static final Push instance = Push._();

  bool available = false;

  /// Appelé quand l'utilisateur touche une notification : (type, requestId).
  void Function(String type, String? requestId)? onOpen;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      available = true;
    } catch (e) {
      debugPrint('Firebase non configuré : $e');
      return;
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_handle);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Laisse le temps à l'interface de se construire
      Future.delayed(const Duration(milliseconds: 800), () => _handle(initial));
    }
  }

  /// Demande l'autorisation et enregistre le jeton de l'appareil pour l'utilisateur connecté.
  Future<void> registerForUser() async {
    if (!available) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      await Api.instance.saveFcmToken(token);
      FirebaseMessaging.instance.onTokenRefresh.listen(Api.instance.saveFcmToken);
    } catch (e) {
      debugPrint('Enregistrement push impossible : $e');
    }
  }

  void _handle(RemoteMessage m) {
    final type = m.data['type'] as String? ?? '';
    final requestId = m.data['request_id'] as String?;
    onOpen?.call(type, (requestId == null || requestId.isEmpty) ? null : requestId);
  }
}
