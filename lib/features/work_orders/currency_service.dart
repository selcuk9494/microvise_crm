import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class CurrencyService {
  // Frankfurter API - ücretsiz ve güvenilir
  static const String _baseUrl = 'https://api.frankfurter.app/latest?from=TRY&to=USD,EUR,GBP';
  
  static Future<Map<String, double>> getExchangeRates() async {
    try {
      final uri = Uri.parse(_baseUrl);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      
      final request = await client.getUrl(uri);
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody) as Map<String, dynamic>;
        final rates = data['rates'] as Map<String, dynamic>?;
        
        if (rates != null) {
          // API TRY bazlı döndürüyor (1 TRY = X USD), biz 1 USD = X TRY istiyoruz
          final usdRate = rates['USD'] as num?;
          final eurRate = rates['EUR'] as num?;
          final gbpRate = rates['GBP'] as num?;
          
          return {
            'USD': usdRate != null ? 1 / usdRate.toDouble() : 34.50,
            'EUR': eurRate != null ? 1 / eurRate.toDouble() : 37.20,
            'GBP': gbpRate != null ? 1 / gbpRate.toDouble() : 43.80,
          };
        }
      }
      client.close();
    } catch (e) {
      debugPrint('Currency fetch error: $e');
    }
    
    // Fallback değerler
    return {
      'USD': 34.50,
      'EUR': 37.20,
      'GBP': 43.80,
    };
  }
}
