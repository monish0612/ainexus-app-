// Integration tests for the REAL runtime glue that powers the credit-card
// forecast: settings banks -> ccBankConfigsProvider -> creditCardForecastProvider,
// fed by the recent-CC-expenses and salary-history streams. This is the data
// path the SalaryScreen actually reads, so it catches wiring regressions the
// pure-engine tests can't.

import 'package:ai_nexus/core/services/credit_card_forecast_engine.dart';
import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/domain/entities/salary_entities.dart';
import 'package:ai_nexus/presentation/providers/salary_providers.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class _FakeRemote implements UserPreferencesService {
  @override
  Future<Map<String, String>?> fetchAll() async => null;
  @override
  Future<bool> pushBatch(Map<String, String> entries) async => true;
}

String _monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

Future<SettingsController> _controllerWithBanks(List<Map<String, dynamic>> banks) async {
  SharedPreferences.setMockInitialValues({'app_banks_v2': jsonEncode(banks)});
  final prefs = await SharedPreferences.getInstance();
  return SettingsController(prefs, _FakeRemote());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ccBankConfigsProvider (derived from synced settings)', () {
    test('keeps only credit cards that have a usable billing cycle', () async {
      final controller = await _controllerWithBanks([
        {'id': 'hdfc_cc', 'name': 'HDFC', 'color': '#004C8F', 'cardType': 'CC', 'statementDay': 18, 'dueDay': 9},
        {'id': 'icici_db', 'name': 'ICICI', 'color': '#B02A2A', 'cardType': 'DB'},
        // A credit card the user saved WITHOUT billing days — must be excluded
        // rather than crash the `statementDay!`/`dueDay!` reads downstream.
        {'id': 'axis_cc', 'name': 'AXIS', 'color': '#97144D', 'cardType': 'CC'},
        {'id': 'cash', 'name': 'CASH', 'color': '#868E96', 'cardType': 'Cash'},
      ]);
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => controller),
      ]);
      addTearDown(container.dispose);

      final configs = container.read(ccBankConfigsProvider);
      expect(configs.length, 1);
      expect(configs.single.name, 'HDFC');
      expect(configs.single.statementDay, 18);
      expect(configs.single.dueDay, 9);
    });
  });

  group('creditCardForecastProvider (settings + expenses + salary)', () {
    test('assembles an active forecast that maps a bill onto a recorded salary',
        () async {
      final now = DateTime.now();
      // Salary recorded for this + the next few months so the bill's repaying
      // month is covered regardless of when the test runs.
      final salaries = <SalaryEntry>[
        for (var i = 0; i <= 3; i++)
          SalaryEntry(
            id: 'm$i',
            month: _monthKey(DateTime(now.year, now.month + i, 1)),
            amount: 100000,
            setAt: '',
          ),
      ];
      final container = ProviderContainer(overrides: [
        ccBankConfigsProvider.overrideWithValue(const [
          BankBillingConfig(name: 'HDFC', statementDay: 18, dueDay: 9),
        ]),
        recentCardExpensesProvider.overrideWith(
          (ref) => Stream.value(<CardExpense>[
            CardExpense(
              bank: 'HDFC',
              amount: 4200,
              date: DateTime(now.year, now.month, now.day),
              description: 'Big Bazaar',
              category: 'Grocery',
            ),
          ]),
        ),
        salaryHistoryStreamProvider.overrideWith((ref) => Stream.value(salaries)),
      ]);
      addTearDown(container.dispose);

      await container.read(recentCardExpensesProvider.future);
      await container.read(salaryHistoryStreamProvider.future);

      final forecast = container.read(creditCardForecastProvider);
      expect(forecast.hasActivity, isTrue);
      expect(forecast.statements.length, 1);
      expect(forecast.statements.single.total, 4200);
      // The contributing charge is attached for drill-down.
      expect(forecast.statements.single.items.single.description, 'Big Bazaar');
      expect(forecast.unconfiguredBanks, isEmpty);
      // The bill lands on a real, recorded salary month within the timeline.
      expect(forecast.timeline.any((m) => m.hasSalary && m.cardBills > 0), isTrue);
    });

    test('flags charges for a bank that has no configured cycle', () async {
      final now = DateTime.now();
      final container = ProviderContainer(overrides: [
        ccBankConfigsProvider.overrideWithValue(const [
          BankBillingConfig(name: 'HDFC', statementDay: 18, dueDay: 9),
        ]),
        recentCardExpensesProvider.overrideWith(
          (ref) => Stream.value(<CardExpense>[
            CardExpense(bank: 'AMEX', amount: 999, date: DateTime(now.year, now.month, now.day)),
          ]),
        ),
        salaryHistoryStreamProvider.overrideWith(
          (ref) => Stream.value(const <SalaryEntry>[]),
        ),
      ]);
      addTearDown(container.dispose);

      await container.read(recentCardExpensesProvider.future);
      await container.read(salaryHistoryStreamProvider.future);

      final forecast = container.read(creditCardForecastProvider);
      expect(forecast.unconfiguredBanks, contains('AMEX'));
      expect(forecast.hasActivity, isFalse);
    });

    test('no CC expenses → inactive forecast (card hides)', () async {
      final container = ProviderContainer(overrides: [
        ccBankConfigsProvider.overrideWithValue(const [
          BankBillingConfig(name: 'HDFC', statementDay: 18, dueDay: 9),
        ]),
        recentCardExpensesProvider.overrideWith(
          (ref) => Stream.value(const <CardExpense>[]),
        ),
        salaryHistoryStreamProvider.overrideWith(
          (ref) => Stream.value(const <SalaryEntry>[]),
        ),
      ]);
      addTearDown(container.dispose);

      await container.read(recentCardExpensesProvider.future);
      await container.read(salaryHistoryStreamProvider.future);

      final forecast = container.read(creditCardForecastProvider);
      expect(forecast.hasActivity, isFalse);
      expect(forecast.statements, isEmpty);
    });
  });
}
