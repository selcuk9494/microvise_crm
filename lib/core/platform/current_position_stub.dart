class CurrentPositionResult {
  const CurrentPositionResult({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

Future<CurrentPositionResult?> fetchCurrentPosition() async {
  return null;
}
