// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

class CurrentPositionResult {
  const CurrentPositionResult({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

Future<CurrentPositionResult?> fetchCurrentPosition() async {
  final geolocation = html.window.navigator.geolocation;
  final completer = Completer<CurrentPositionResult?>();
  geolocation
      .getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 10),
        maximumAge: Duration.zero,
      )
      .then((position) {
        completer.complete(
          CurrentPositionResult(
            latitude: (position.coords?.latitude ?? 0).toDouble(),
            longitude: (position.coords?.longitude ?? 0).toDouble(),
          ),
        );
      })
      .catchError((_) {
        completer.complete(null);
      });

  return completer.future;
}
