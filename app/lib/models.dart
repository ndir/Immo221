// Modèles de données et libellés.

const transactionLabels = {
  'location': 'Location',
  'colocation': 'Colocation',
  'achat': 'Achat',
  'terrain': 'Terrain',
};

const propertyLabels = {
  'chambre': 'Chambre',
  'studio': 'Studio',
  'appartement': 'Appartement',
  'maison': 'Maison',
  'villa': 'Villa',
  'terrain': 'Terrain',
  'local_commercial': 'Local commercial',
  'autre': 'Autre',
};

const roleLabels = {
  'seeker': 'Demandeur',
  'owner': 'Propriétaire',
  'broker': 'Démarcheur',
  'agency': 'Agence',
  'admin': 'Équipe Dëkk',
};

const statusLabels = {
  'draft': 'À vérifier',
  'published': 'En ligne',
  'found': 'Trouvé',
  'expired': 'Expirée',
  'removed': 'Retirée',
  'failed': 'Traitement échoué',
};

int? _int(dynamic v) => v == null ? null : (v as num).toInt();
double _double(dynamic v) => v == null ? 0 : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
List<int> _ints(dynamic v) => (v as List?)?.map((e) => (e as num).toInt()).toList() ?? <int>[];
List<String> _strings(dynamic v) => (v as List?)?.map((e) => e.toString()).toList() ?? <String>[];

/// « 300000 » → « 300 000 F » ; « 25000000 » → « 25 M FCFA ».
String fcfa(int? amount, {String? period}) {
  if (amount == null) return '';
  String text;
  if (amount >= 1000000 && amount % 100000 == 0) {
    final m = amount / 1000000;
    text = '${m == m.roundToDouble() ? m.toInt() : m.toStringAsFixed(1).replaceAll('.', ',')} M FCFA';
  } else {
    final s = amount.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    text = '$buf F';
  }
  return period == 'mois' ? '$text / mois' : text;
}

String ago(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays == 1) return 'hier';
  return 'il y a ${diff.inDays} j';
}

class Zone {
  final int id;
  final String name;
  final String city;
  final String region;
  const Zone({required this.id, required this.name, required this.city, required this.region});

  factory Zone.fromJson(Map<String, dynamic> j) =>
      Zone(id: _int(j['id'])!, name: j['name'] as String, city: j['city'] as String, region: j['region'] as String);

  String get label => name == city ? name : '$name ($city)';
}

class SeekerRequest {
  final String id;
  final String status;
  final String? transcript;
  final String? summary;
  final String? transaction;
  final String? property;
  final List<int> zoneIds;
  final String? zoneFreeText;
  final int? budgetMin;
  final int? budgetMax;
  final String? budgetPeriod;
  final int? bedroomsMin;
  final bool? furnished;
  final String? moveIn;
  final bool isUrgent;
  final int contactsCount;
  final int maxContacts;
  final int listenCount;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  SeekerRequest.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        status = j['status'] as String,
        transcript = j['transcript'] as String?,
        summary = j['summary'] as String?,
        transaction = j['transaction'] as String?,
        property = j['property'] as String?,
        zoneIds = _ints(j['zone_ids']),
        zoneFreeText = j['zone_free_text'] as String?,
        budgetMin = _int(j['budget_min']),
        budgetMax = _int(j['budget_max']),
        budgetPeriod = j['budget_period'] as String?,
        bedroomsMin = _int(j['bedrooms_min']),
        furnished = j['furnished'] as bool?,
        moveIn = j['move_in'] as String?,
        isUrgent = (j['is_urgent'] as bool?) ?? false,
        contactsCount = _int(j['contacts_count']) ?? 0,
        maxContacts = _int(j['max_contacts']) ?? 5,
        listenCount = _int(j['listen_count']) ?? 0,
        expiresAt = _date(j['expires_at']),
        createdAt = _date(j['created_at']);

  bool get isActive => status == 'published' && (expiresAt?.isAfter(DateTime.now()) ?? false);
}

class FeedItem {
  final String id;
  final String? transaction;
  final String? property;
  final List<int> zoneIds;
  final List<String> zoneNames;
  final String? city;
  final String? zoneFreeText;
  final int? budgetMin;
  final int? budgetMax;
  final String? budgetPeriod;
  final int? bedroomsMin;
  final bool? furnished;
  final String? moveIn;
  final bool isUrgent;
  final String? summary;
  final String? transcript;
  final String audioPath;
  final int? audioDurationS;
  final int contactsCount;
  final int maxContacts;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final String? seekerFirstName;
  final bool alreadyUnlocked;

  FeedItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        transaction = j['transaction'] as String?,
        property = j['property'] as String?,
        zoneIds = _ints(j['zone_ids']),
        zoneNames = _strings(j['zone_names']),
        city = j['city'] as String?,
        zoneFreeText = j['zone_free_text'] as String?,
        budgetMin = _int(j['budget_min']),
        budgetMax = _int(j['budget_max']),
        budgetPeriod = j['budget_period'] as String?,
        bedroomsMin = _int(j['bedrooms_min']),
        furnished = j['furnished'] as bool?,
        moveIn = j['move_in'] as String?,
        isUrgent = (j['is_urgent'] as bool?) ?? false,
        summary = j['summary'] as String?,
        transcript = j['transcript'] as String?,
        audioPath = j['audio_path'] as String,
        audioDurationS = _int(j['audio_duration_s']),
        contactsCount = _int(j['contacts_count']) ?? 0,
        maxContacts = _int(j['max_contacts']) ?? 5,
        publishedAt = _date(j['published_at']),
        expiresAt = _date(j['expires_at']),
        seekerFirstName = j['seeker_first_name'] as String?,
        alreadyUnlocked = (j['already_unlocked'] as bool?) ?? false;

  String get place => zoneNames.isNotEmpty ? zoneNames.join(', ') : (zoneFreeText ?? 'Zone non précisée');

  String get tag {
    final t = transactionLabels[transaction] ?? 'Recherche';
    final where = city ?? (zoneNames.isNotEmpty ? zoneNames.first : null);
    return [if (isUrgent) 'Urgent', t, if (where != null && where != 'Dakar') where].join(' · ');
  }

  String get title => summary ?? '${propertyLabels[property] ?? 'Bien'} · $place';

  String get duration {
    final s = audioDurationS ?? 0;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class AppNotification {
  final int id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime? createdAt;

  AppNotification.fromJson(Map<String, dynamic> j)
      : id = _int(j['id'])!,
        type = j['type'] as String,
        title = j['title'] as String,
        body = j['body'] as String,
        data = (j['data'] as Map?)?.cast<String, dynamic>() ?? {},
        readAt = _date(j['read_at']),
        createdAt = _date(j['created_at']);

  String? get requestId => data['request_id'] as String?;
}

class ContactRow {
  final String ownerId;
  final String ownerName;
  final String ownerRole;
  final bool isVerified;
  final double ratingAvg;
  final int ratingCount;
  final DateTime? createdAt;

  ContactRow.fromJson(Map<String, dynamic> j)
      : ownerId = j['owner_id'] as String,
        ownerName = (j['owner_name'] as String?)?.trim().isNotEmpty == true ? j['owner_name'] as String : 'Offreur',
        ownerRole = j['owner_role'] as String? ?? 'owner',
        isVerified = (j['is_verified'] as bool?) ?? false,
        ratingAvg = _double(j['rating_avg']),
        ratingCount = _int(j['rating_count']) ?? 0,
        createdAt = _date(j['created_at']);

  String get subtitle {
    final role = roleLabels[ownerRole] ?? '';
    final rating = ratingCount > 0 ? ' · ${ratingAvg.toStringAsFixed(1).replaceAll('.', ',')} ★' : ' · Nouveau';
    return '$role${isVerified ? ' vérifié(e)' : ''}$rating';
  }
}

class UnlockRow {
  final String requestId;
  final String outcome;
  final String requestStatus;
  final String? summary;
  final String zoneLabel;
  final String? seekerFirstName;
  final String? seekerWhatsapp;
  final DateTime? createdAt;

  UnlockRow.fromJson(Map<String, dynamic> j)
      : requestId = j['request_id'] as String,
        outcome = j['outcome'] as String,
        requestStatus = j['request_status'] as String,
        summary = j['summary'] as String?,
        zoneLabel = j['zone_label'] as String? ?? '',
        seekerFirstName = j['seeker_first_name'] as String?,
        seekerWhatsapp = j['seeker_whatsapp'] as String?,
        createdAt = _date(j['created_at']);
}

class Subscription {
  final int id;
  final int zoneId;
  final String? transaction;
  Subscription.fromJson(Map<String, dynamic> j)
      : id = _int(j['id'])!,
        zoneId = _int(j['zone_id'])!,
        transaction = j['transaction'] as String?;
}
