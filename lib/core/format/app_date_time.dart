DateTime? parseAppDateTime(String? raw, {int fixedOffsetHours = 2}) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;

  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;

  final hasTimeComponent = text.contains('T');
  if (!hasTimeComponent) return parsed;

  final utc = parsed.isUtc ? parsed : parsed.toUtc();
  return utc.add(Duration(hours: fixedOffsetHours));
}

DateTime appNow({int fixedOffsetHours = 2}) {
  return DateTime.now().toUtc().add(Duration(hours: fixedOffsetHours));
}

DateTime normalizeAppDate(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}
