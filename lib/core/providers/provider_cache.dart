import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider sonucunu belirli süre bellekte tutar; sayfa geçişlerinde yeniden fetch'i azaltır.
void keepProviderAliveFor(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  final timer = Timer(duration, link.close);
  ref.onDispose(timer.cancel);
}
