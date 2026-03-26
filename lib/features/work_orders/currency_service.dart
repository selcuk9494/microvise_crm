import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CurrencyService {
  static const String _baseUrl = 'https://api.frankfurter.app/latest?from=TRY&to=USD,EUR,GBP';
  
  static Future<Map<String, double>> getExchangeRates() async {
    try {
      final response = await http.get(Uri.parse(_baseUrl)).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rates = data['rates'] as Map<String, dynamic>?;
        
        if (rates != null) {
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
    } catch (e) {
      debugPrint('Currency fetch error: $e');
    }
    
    return {
      'USD': 34.50,
      'EUR': 37.20,
      'GBP': 43.80,
    };
  }
}
