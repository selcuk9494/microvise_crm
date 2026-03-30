import 'application_form_model.dart';

enum ApplicationPrintKind { kdv, kdv4a }

extension ApplicationPrintKindLabel on ApplicationPrintKind {
  String get label => this == ApplicationPrintKind.kdv ? 'KDV4' : 'KDV4A';
}

Future<bool> printApplicationForm(
  ApplicationFormRecord record, {
  required ApplicationPrintKind kind,
  ApplicationFormPrintSettings? settings,
}) async {
  return false;
}
