// Verifies the extended Bank model round-trips through local SharedPreferences
// as JSON (carrying cardType + billing cycle), is backward-compatible with the
// legacy `id|name|color` StringList, and that add/update/delete keep the synced
// JSON in step.

import 'dart:convert';

import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRemote implements UserPreferencesService {
  Map<String, String>? remote;
  final List<Map<String, String>> pushes = [];

  @override
  Future<Map<String, String>?> fetchAll() async => remote;

  @override
  Future<bool> pushBatch(Map<String, String> entries) async {
    pushes.add(Map<String, String>.from(entries));
    return true;
  }
}

Future<SettingsController> _make(_FakeRemote remote) async {
  final prefs = await SharedPreferences.getInstance();
  return SettingsController(prefs, remote);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hydrates the new JSON format with cardType + billing cycle', () async {
    final banksJson = jsonEncode([
      {'id': 'hdfc_cc', 'name': 'HDFC', 'color': '#004C8F', 'cardType': 'CC', 'statementDay': 18, 'dueDay': 9},
      {'id': 'icici_db', 'name': 'ICICI', 'color': '#B02A2A', 'cardType': 'DB'},
    ]);
    SharedPreferences.setMockInitialValues({'app_banks_v2': banksJson});

    final c = await _make(_FakeRemote());
    final banks = c.state.banks;
    expect(banks.length, 2);

    final hdfc = banks.firstWhere((b) => b.id == 'hdfc_cc');
    expect(hdfc.cardType, kCardTypeCredit);
    expect(hdfc.statementDay, 18);
    expect(hdfc.dueDay, 9);
    expect(hdfc.isCreditCard, isTrue);

    final icici = banks.firstWhere((b) => b.id == 'icici_db');
    expect(icici.cardType, kCardTypeDebit);
    expect(icici.statementDay, isNull);
    expect(icici.isCreditCard, isFalse);
  });

  test('migrates the legacy id|name|color StringList (defaults to DB)', () async {
    SharedPreferences.setMockInitialValues({
      'app_banks': ['b1|HDFC|#004C8F', 'b2|ICICI|#B02A2A'],
    });

    final c = await _make(_FakeRemote());
    final banks = c.state.banks;
    expect(banks.length, 2);
    expect(banks.first.name, 'HDFC');
    expect(banks.first.cardType, kCardTypeDebit);
    expect(banks.every((b) => !b.isCreditCard), isTrue);
  });

  test('seeds defaults on a totally fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await _make(_FakeRemote());
    expect(c.state.banks, isNotEmpty);
    // The default set must include at least one configured credit card.
    expect(c.state.banks.any((b) => b.isCreditCard), isTrue);
  });

  test('addBank persists JSON and queues the synced value', () async {
    SharedPreferences.setMockInitialValues({'app_banks_v2': jsonEncode(const [])});
    final remote = _FakeRemote();
    final prefs = await SharedPreferences.getInstance();
    final c = SettingsController(prefs, remote);

    c.addBank('AXIS', cardType: kCardTypeCredit, statementDay: 24, dueDay: 13);

    final added = c.state.banks.single;
    expect(added.name, 'AXIS');
    expect(added.cardType, kCardTypeCredit);
    expect(added.statementDay, 24);
    expect(added.dueDay, 13);

    // Local JSON store reflects the new card and round-trips back.
    final stored = prefs.getString('app_banks_v2');
    expect(stored, isNotNull);
    final decoded = (jsonDecode(stored!) as List).cast<Map<String, dynamic>>();
    expect(decoded.single['cardType'], 'CC');
    expect(decoded.single['statementDay'], 24);
  });

  test('updateBank to a debit card clears the billing cycle', () async {
    SharedPreferences.setMockInitialValues({
      'app_banks_v2': jsonEncode([
        {'id': 'x', 'name': 'HDFC', 'color': '#004C8F', 'cardType': 'CC', 'statementDay': 18, 'dueDay': 9},
      ]),
    });
    final c = await _make(_FakeRemote());

    c.updateBank('x', cardType: kCardTypeDebit);
    final updated = c.state.banks.single;
    expect(updated.cardType, kCardTypeDebit);
    expect(updated.statementDay, isNull);
    expect(updated.dueDay, isNull);
    expect(updated.isCreditCard, isFalse);
  });

  test('deleteBank removes the entry', () async {
    SharedPreferences.setMockInitialValues({
      'app_banks_v2': jsonEncode([
        {'id': 'a', 'name': 'HDFC', 'color': '#004C8F', 'cardType': 'DB'},
        {'id': 'b', 'name': 'AXIS', 'color': '#97144D', 'cardType': 'DB'},
      ]),
    });
    final c = await _make(_FakeRemote());

    c.deleteBank('a');
    expect(c.state.banks.length, 1);
    expect(c.state.banks.single.id, 'b');
  });

  test('clamps out-of-range billing days', () async {
    SharedPreferences.setMockInitialValues({'app_banks_v2': jsonEncode(const [])});
    final c = await _make(_FakeRemote());

    c.addBank('TEST', cardType: kCardTypeCredit, statementDay: 99, dueDay: 0);
    final b = c.state.banks.single;
    expect(b.statementDay, 31);
    expect(b.dueDay, 1);
  });

  test('add/delete pushes the banks blob to the remote (cross-device sync)',
      () async {
    SharedPreferences.setMockInitialValues({'app_banks_v2': jsonEncode(const [])});
    final remote = _FakeRemote();
    final prefs = await SharedPreferences.getInstance();
    final c = SettingsController(prefs, remote);

    c.addBank('KOTAK', cardType: kCardTypeCredit, statementDay: 5, dueDay: 25);
    // Let the 600ms debounce timer fire and the async push complete.
    await Future<void>.delayed(const Duration(milliseconds: 750));

    expect(remote.pushes, isNotEmpty);
    final pushed = remote.pushes.last;
    expect(pushed.containsKey('app_banks'), isTrue,
        reason: 'banks must be queued under the cross-device app_banks key');
    final decoded =
        (jsonDecode(pushed['app_banks']!) as List).cast<Map<String, dynamic>>();
    expect(decoded.single['name'], 'KOTAK');
    expect(decoded.single['cardType'], 'CC');
    expect(decoded.single['statementDay'], 5);

    final id = c.state.banks.single.id;
    c.deleteBank(id);
    await Future<void>.delayed(const Duration(milliseconds: 750));

    // The latest push reflects the deletion (now an empty bank list).
    final afterDelete =
        (jsonDecode(remote.pushes.last['app_banks']!) as List);
    expect(afterDelete, isEmpty);
  });
}
