import 'package:dekk/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fcfa formate les montants', () {
    expect(fcfa(300000), '300 000 F');
    expect(fcfa(300000, period: 'mois'), '300 000 F / mois');
    expect(fcfa(25000000), '25 M FCFA');
    expect(fcfa(1500000), '1,5 M FCFA');
    expect(fcfa(null), '');
  });

  test('FeedItem : étiquette et titre', () {
    final f = FeedItem.fromJson({
      'id': 'x',
      'transaction': 'terrain',
      'property': 'terrain',
      'zone_ids': [6],
      'zone_names': ['Thiès'],
      'city': 'Thiès',
      'is_urgent': true,
      'summary': null,
      'audio_path': 'u/x.m4a',
      'audio_duration_s': 52,
      'contacts_count': 1,
      'max_contacts': 5,
      'already_unlocked': false,
    });
    expect(f.tag, 'Urgent · Terrain · Thiès');
    expect(f.title, 'Terrain · Thiès');
    expect(f.duration, '0:52');
  });

  test('ContactRow : sous-titre', () {
    final c = ContactRow.fromJson({
      'owner_id': 'o',
      'owner_name': 'Immo Sacré-Cœur',
      'owner_role': 'agency',
      'is_verified': true,
      'rating_avg': 4.7,
      'rating_count': 23,
    });
    expect(c.subtitle, 'Agence vérifié(e) · 4,7 ★');
  });
}
