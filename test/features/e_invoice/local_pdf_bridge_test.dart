import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/features/e_invoice/local_pdf_bridge.dart';

void main() {
  test('bulut CRM local open-pdf kullanmaz', () {
    expect(
      canUseLocalOpenPdfBridge(
        base: Uri.parse('https://crm.microvise.net/'),
        isWeb: true,
      ),
      isFalse,
    );
  });

  test('localhost ve Electron file:// local open-pdf kullanır', () {
    expect(
      canUseLocalOpenPdfBridge(
        base: Uri.parse('http://127.0.0.1:4000/'),
        isWeb: true,
      ),
      isTrue,
    );
    expect(
      canUseLocalOpenPdfBridge(
        base: Uri.parse('file:///Applications/Microvise.app/index.html'),
        isWeb: true,
      ),
      isTrue,
    );
  });

  test('mobil native local open-pdf kullanmaz', () {
    expect(
      canUseLocalOpenPdfBridge(
        base: Uri.parse('https://crm.microvise.net/'),
        isWeb: false,
      ),
      isFalse,
    );
  });
}
