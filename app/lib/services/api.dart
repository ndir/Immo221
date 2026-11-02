import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

/// Toutes les lectures et écritures passent par ici.
/// La sécurité est assurée côté base (RLS et fonctions SQL).
class Api {
  Api._();
  static final Api instance = Api._();

  SupabaseClient get sb => Supabase.instance.client;
  String? get uid => sb.auth.currentUser?.id;

  List<Zone> _zones = [];
  bool freeMode = true;

  // ---------------------------------------------------------------------------
  // Connexion
  // ---------------------------------------------------------------------------
  Future<void> sendCode(String phone) => sb.auth.signInWithOtp(phone: phone);

  Future<void> verifyCode(String phone, String code, {String? name}) async {
    await sb.auth.verifyOTP(phone: phone, token: code, type: OtpType.sms);
    if (name != null && name.trim().isNotEmpty) {
      await sb.from('profiles').update({'display_name': name.trim()}).eq('id', uid!);
    }
  }

  Future<void> signOut() async {
    if (uid != null) {
      await sb.from('profiles').update({'fcm_token': null}).eq('id', uid!);
    }
    await sb.auth.signOut();
  }

  Future<Map<String, dynamic>?> myProfile() async {
    if (uid == null) return null;
    return await sb.from('profiles').select().eq('id', uid!).maybeSingle();
  }

  Future<void> setRole(String role) => sb.rpc('set_my_role', params: {'p_role': role});

  Future<void> updateProfile(Map<String, dynamic> values) => sb.from('profiles').update(values).eq('id', uid!);

  Future<void> saveFcmToken(String? token) async {
    if (uid == null) return;
    await sb.from('profiles').update({'fcm_token': token}).eq('id', uid!);
  }

  // ---------------------------------------------------------------------------
  // Référentiels
  // ---------------------------------------------------------------------------
  Future<List<Zone>> zones() async {
    if (_zones.isNotEmpty) return _zones;
    final rows = await sb.from('zones').select('id, name, city, region').order('city').order('name');
    _zones = rows.map(Zone.fromJson).toList();
    return _zones;
  }

  Zone? zoneById(int id) {
    for (final z in _zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  Future<void> loadSettings() async {
    final row = await sb.from('app_settings').select('free_mode').maybeSingle();
    freeMode = (row?['free_mode'] as bool?) ?? true;
  }

  // ---------------------------------------------------------------------------
  // Demandeur
  // ---------------------------------------------------------------------------

  /// Envoie le vocal, crée la demande et lance le traitement IA.
  Future<SeekerRequest> createAndProcess(File audio, Duration duration) async {
    final id = _uuid();
    final path = '$uid/$id.m4a';
    await sb.storage.from('voice-requests').uploadBinary(
          path,
          await audio.readAsBytes(),
          fileOptions: const FileOptions(contentType: 'audio/mp4'),
        );
    await sb.from('requests').insert({
      'id': id,
      'audio_path': path,
      'source': 'app',
      'audio_duration_s': duration.inSeconds.clamp(1, 180),
    });
    return process(id);
  }

  Future<SeekerRequest> process(String requestId) async {
    final res = await sb.functions.invoke('process-voice', body: {'request_id': requestId});
    final data = (res.data as Map).cast<String, dynamic>();
    return SeekerRequest.fromJson((data['request'] as Map).cast<String, dynamic>());
  }

  Future<SeekerRequest> publish({
    required String requestId,
    required String transaction,
    String? property,
    required List<int> zoneIds,
    String? zoneFreeText,
    int? budgetMin,
    int? budgetMax,
    String? budgetPeriod,
    int? bedroomsMin,
    bool? furnished,
    String? moveIn,
    String? summary,
    int visibilityDays = 15,
    bool isUrgent = false,
    bool userEdited = false,
  }) async {
    final row = await sb.rpc('publish_request', params: {
      'p_request_id': requestId,
      'p_transaction': transaction,
      'p_property': property,
      'p_zone_ids': zoneIds,
      'p_zone_free_text': zoneFreeText,
      'p_budget_min': budgetMin,
      'p_budget_max': budgetMax,
      'p_budget_period': budgetPeriod,
      'p_bedrooms_min': bedroomsMin,
      'p_furnished': furnished,
      'p_move_in': moveIn,
      'p_summary': summary,
      'p_visibility_days': visibilityDays,
      'p_is_urgent': isUrgent,
      'p_user_edited': userEdited,
    });
    return SeekerRequest.fromJson((row as Map).cast<String, dynamic>());
  }

  Future<List<SeekerRequest>> myRequests() async {
    final rows = await sb
        .from('requests')
        .select()
        .inFilter('status', ['draft', 'published', 'found', 'expired', 'failed'])
        .order('created_at', ascending: false)
        .limit(30);
    return rows.map(SeekerRequest.fromJson).toList();
  }

  Future<String> signedAudioUrl(String path) => sb.storage.from('voice-requests').createSignedUrl(path, 900);

  Future<List<ContactRow>> contacts(String requestId) async {
    final rows = await sb.from('my_request_contacts').select().eq('request_id', requestId).order('created_at');
    return rows.map(ContactRow.fromJson).toList();
  }

  Future<void> extend(String requestId, {int days = 15}) =>
      sb.rpc('extend_request', params: {'p_request_id': requestId, 'p_days': days});

  Future<void> close(String requestId, {String? helpedOwner, int? rating}) => sb.rpc('close_request',
      params: {'p_request_id': requestId, 'p_helped_owner': helpedOwner, 'p_rating': rating});

  Future<void> remove(String requestId) => sb.rpc('remove_request', params: {'p_request_id': requestId});

  Future<void> report(String ownerId, {String? requestId, String? reason}) => sb.rpc('report_owner',
      params: {'p_owner': ownerId, 'p_request_id': requestId, 'p_reason': reason});

  // ---------------------------------------------------------------------------
  // Offreur
  // ---------------------------------------------------------------------------
  Future<List<FeedItem>> feed() async {
    final rows = await sb.from('feed').select().order('published_at', ascending: false).limit(100);
    return rows.map(FeedItem.fromJson).toList();
  }

  Future<FeedItem?> feedItem(String id) async {
    final row = await sb.from('feed').select().eq('id', id).maybeSingle();
    return row == null ? null : FeedItem.fromJson(row);
  }

  Future<void> registerListen(String requestId) => sb.rpc('register_listen', params: {'p_request_id': requestId});

  /// Retourne { whatsapp_phone, seeker_name, message, already_unlocked }.
  Future<Map<String, dynamic>> unlock(String requestId) async {
    final res = await sb.rpc('unlock_contact', params: {'p_request_id': requestId});
    return (res as Map).cast<String, dynamic>();
  }

  Future<List<UnlockRow>> myUnlocks() async {
    final rows = await sb.from('my_unlocks').select().order('created_at', ascending: false);
    return rows.map(UnlockRow.fromJson).toList();
  }

  Future<void> setOutcome(String requestId, String outcome) =>
      sb.rpc('set_unlock_outcome', params: {'p_request_id': requestId, 'p_outcome': outcome});

  Future<List<Subscription>> subscriptions() async {
    final rows = await sb.from('owner_subscriptions').select().eq('owner_id', uid!);
    return rows.map(Subscription.fromJson).toList();
  }

  Future<void> subscribe(int zoneId, {String? transaction}) =>
      sb.from('owner_subscriptions').insert({'zone_id': zoneId, 'transaction': transaction});

  Future<void> unsubscribe(int subscriptionId) => sb.from('owner_subscriptions').delete().eq('id', subscriptionId);

  // ---------------------------------------------------------------------------
  // Notifications et réglages
  // ---------------------------------------------------------------------------
  Stream<List<AppNotification>> notificationsStream() => sb
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid!)
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => rows.map(AppNotification.fromJson).toList());

  Future<void> markRead([List<int>? ids]) => sb.rpc('mark_notifications_read', params: {'p_ids': ids});

  Future<Map<String, dynamic>> userSettings() async =>
      await sb.from('user_settings').select().eq('user_id', uid!).maybeSingle() ??
      {'instant_alerts': true, 'quiet_hours': true, 'daily_listen_digest': false};

  Future<void> updateUserSettings(Map<String, dynamic> values) =>
      sb.from('user_settings').update(values).eq('user_id', uid!);

  Future<Map<String, bool>> notificationPrefs() async {
    final rows = await sb.from('notification_prefs').select('type, enabled').eq('user_id', uid!);
    return {for (final r in rows) r['type'] as String: r['enabled'] as bool};
  }

  Future<void> setNotificationPref(String type, bool enabled) => sb
      .from('notification_prefs')
      .upsert({'user_id': uid, 'type': type, 'enabled': enabled}, onConflict: 'user_id,type');

  // ---------------------------------------------------------------------------
  static String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    final s = List.generate(16, h).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}

/// Message lisible pour l'utilisateur à partir d'une erreur.
String friendlyError(Object e) {
  String raw;
  if (e is PostgrestException) {
    raw = e.message;
  } else if (e is AuthException) {
    raw = e.message;
  } else if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['message'] is String) return d['message'] as String;
    raw = '${e.status} ${e.details}';
  } else if (e is SocketException) {
    return 'Pas de connexion. Vérifiez votre réseau et réessayez.';
  } else {
    raw = e.toString();
  }
  const map = {
    'contacts_full': 'Cette demande a déjà reçu tous ses contacts.',
    'request_closed': "Cette demande n'est plus active.",
    'daily_limit_reached': 'Limite de contacts du jour atteinte. Réessayez demain.',
    'subscription_required': 'Un forfait est nécessaire pour contacter ce demandeur.',
    'account_suspended': 'Votre compte est suspendu. Contactez le support Dëkk.',
    'not_offerer': 'Cette action est réservée aux offreurs.',
    'own_request': "C'est votre propre demande.",
    'transaction_required': "Précisez : location, colocation, achat ou terrain.",
    'zone_required': 'Indiquez au moins un quartier ou une ville.',
    'invalid_budget': 'Le budget minimum dépasse le budget maximum.',
    'request_not_found': 'Demande introuvable.',
    'owner_not_in_contacts': "Cet offreur ne vous a pas contacté.",
  };
  for (final entry in map.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }
  if (raw.contains('Token has expired') || raw.contains('invalid') && raw.toLowerCase().contains('otp')) {
    return 'Code incorrect ou expiré.';
  }
  return 'Une erreur est survenue. Réessayez.';
}
