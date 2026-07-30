// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<bool> openExternalUrl(String url) async {
  final opened = html.window.open(url, '_blank');
  // Açılır pencere engellendiğinde tarayıcı null döndürür; dart:html bunu
  // tip imzasına yansıtmadığı için dinamik karşılaştırma gerekir.
  return (opened as dynamic) != null;
}
