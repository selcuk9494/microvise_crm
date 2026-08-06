import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/api/api_client.dart';

class CurrencyService {
  /// Son çare sabitler (Halkbank / Frankfurter yoksa). Güncel piyasa yakını.
  static const Map<String, double> _hardcodedFallback = {
    'USD': 49.0,
    'EUR': 56.5,
    'GBP': 66.0,
  };

  static const String _frankfurterUrl =
      'https://api.frankfurter.dev/v1/latest?base=TRY&symbols=USD,EUR,GBP';

  /// TRY karşılığı satış kurları (1 USD/EUR/GBP = X TRY).
  /// Tercih sırası: CRM Halkbank API → Frankfurter → sabit.
  static Future<Map<String, double>> getExchangeRates({
    ApiClient? apiClient,
  }) async {
    final fromHalkbank = await _fromHalkbank(apiClient);
    if (fromHalkbank != null) return fromHalkbank;

    final fromFrankfurter = await _fromFrankfurter();
    if (fromFrankfurter != null) return fromFrankfurter;

    return Map<String, double>.from(_hardcodedFallback);
  }

  static Future<Map<String, double>?> _fromHalkbank(ApiClient? apiClient) async {
    if (apiClient == null) return null;
    try {
      final response = await apiClient.getJson(
        '/data',
        queryParameters: const {'resource': 'halkbank_exchange_rates'},
      );
      final items = response['items'];
      if (items is! List || items.isEmpty) return null;

      final out = <String, double>{};
      for (final raw in items) {
        if (raw is! Map) continue;
        final code = (raw['code'] ?? '').toString().trim().toUpperCase();
        if (code.isEmpty || code == 'TRY') continue;
        final selling = _toDouble(raw['selling']);
        if (selling == null || selling <= 0) continue;
        out[code] = selling;
      }
      if (out.containsKey('USD') ||
          out.containsKey('EUR') ||
          out.containsKey('GBP')) {
        return {
          'USD': out['USD'] ?? _hardcodedFallback['USD']!,
          'EUR': out['EUR'] ?? _hardcodedFallback['EUR']!,
          'GBP': out['GBP'] ?? _hardcodedFallback['GBP']!,
        };
      }
    } catch (e) {
      debugPrint('Halkbank kur okuma hatası: $e');
    }
    return null;
  }

  static Future<Map<String, double>?> _fromFrankfurter() async {
    try {
      final response = await http
          .get(Uri.parse(_frankfurterUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final rates = data['rates'] as Map<String, dynamic>?;
      if (rates == null) return null;

      final usdRate = rates['USD'] as num?;
      final eurRate = rates['EUR'] as num?;
      final gbpRate = rates['GBP'] as num?;
      if (usdRate == null && eurRate == null && gbpRate == null) return null;

      // base=TRY → rates are foreign per 1 TRY; invert to TRY per foreign unit.
      return {
        'USD': usdRate != null && usdRate > 0
            ? 1 / usdRate.toDouble()
            : _hardcodedFallback['USD']!,
        'EUR': eurRate != null && eurRate > 0
            ? 1 / eurRate.toDouble()
            : _hardcodedFallback['EUR']!,
        'GBP': gbpRate != null && gbpRate > 0
            ? 1 / gbpRate.toDouble()
            : _hardcodedFallback['GBP']!,
      };
    } catch (e) {
      debugPrint('Frankfurter kur okuma hatası: $e');
      return null;
    }
  }

  static double? _toDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }
}
