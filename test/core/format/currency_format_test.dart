import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/core/format/currency_format.dart';

void main() {
  group('parseCurrencyValue', () {
    test('treats comma and period as decimal', () {
      expect(parseCurrencyValue('11,25'), 11.25);
      expect(parseCurrencyValue('11.25'), 11.25);
      expect(parseCurrencyValue('12,5'), 12.50);
      expect(parseCurrencyValue('12.5'), 12.50);
      expect(parseCurrencyValue('0,35'), 0.35);
      expect(parseCurrencyValue('0.35'), 0.35);
    });

    test('reads TR and US grouped money', () {
      expect(parseCurrencyValue('1.234,56'), 1234.56);
      expect(parseCurrencyValue('1,234.56'), 1234.56);
      expect(parseCurrencyValue('1.234.567,89'), 1234567.89);
    });

    test('reads a single 3-digit separator as thousands', () {
      expect(parseCurrencyValue('1.234'), 1234);
      expect(parseCurrencyValue('1,234'), 1234);
    });

    test('keeps a leading-zero fraction as decimal', () {
      expect(parseCurrencyValue('0.350'), 0.35);
      expect(parseCurrencyValue('0,350'), 0.35);
    });

    test('ignores currency text and spaces', () {
      expect(parseCurrencyValue('  11,25 TL '), 11.25);
      expect(parseCurrencyValue('-11,25'), -11.25);
    });
  });

  group('formatMoneyInput', () {
    test('writes a Turkish decimal comma', () {
      expect(formatMoneyInput(11.25), '11,25');
      expect(formatMoneyInput(1234.5), '1234,50');
      expect(formatMoneyInput(0), '0,00');
    });
  });

  group('MoneyDecimalInputFormatter', () {
    const formatter = MoneyDecimalInputFormatter();

    TextEditingValue apply(String text) {
      return formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
    }

    test('converts a typed period to a comma', () {
      expect(apply('11.25').text, '11,25');
      expect(apply('11,25').text, '11,25');
    });

    test('normalizes mixed pasted money', () {
      expect(apply('1.234,56').text, '1234,56');
      expect(apply('1,234.56').text, '1234,56');
    });

    test('keeps two fraction digits', () {
      expect(apply('11.256').text, '11,25');
    });
  });
}
