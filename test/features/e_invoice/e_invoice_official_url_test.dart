import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/features/e_invoice/e_invoice_official_url.dart';

void main() {
  test('builds test verification URL', () {
    expect(
      buildOfficialEInvoiceUrl(
        verificationCode: '019fa939-5333-7454-a0f2-dada84902127',
        environment: 'test',
      ),
      'https://test-efatura.maliye.gov.ct.tr/dogrula/'
      '?code=019fa939-5333-7454-a0f2-dada84902127',
    );
  });

  test('builds production verification URL', () {
    expect(
      buildOfficialEInvoiceUrl(
        verificationCode: '019fa939-5333-7454-a0f2-dada84902127',
        environment: 'production',
      ),
      'https://efatura.maliye.gov.ct.tr/dogrula/'
      '?code=019fa939-5333-7454-a0f2-dada84902127',
    );
  });

  test('returns null without verification code', () {
    expect(
      buildOfficialEInvoiceUrl(
        verificationCode: ' ',
        environment: 'production',
      ),
      isNull,
    );
  });
}
