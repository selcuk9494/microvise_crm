// Calendar / timestamp helpers that preserve the user's local day.
//
// Postgres `date` values often arrive as `YYYY-MM-DD` or as UTC midnight
// (`YYYY-MM-DDT00:00:00.000Z`). Parsing those as UTC and formatting in a
// UTC+3 locale shows the previous evening (e.g. 31.07 21:00 / 23:00).

DateTime? parseAppDateTime(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;

  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (dateOnly != null) {
    return DateTime(
      int.parse(dateOnly.group(1)!),
      int.parse(dateOnly.group(2)!),
      int.parse(dateOnly.group(3)!),
    );
  }

  // node-pg serializes `date` as midnight UTC ISO — keep the calendar day.
  final utcMidnight = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ]00:00:00(?:\.\d+)?(?:Z|[+-]00:00)?$',
  ).firstMatch(text);
  if (utcMidnight != null) {
    return DateTime(
      int.parse(utcMidnight.group(1)!),
      int.parse(utcMidnight.group(2)!),
      int.parse(utcMidnight.group(3)!),
    );
  }

  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return parsed.toLocal();
}

DateTime appNow() => DateTime.now();

DateTime normalizeAppDate(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  return DateTime(local.year, local.month, local.day);
}

/// Local calendar day as `yyyy-MM-dd` (never UTC-shifted via toIso8601String).
String formatAppDateIso(DateTime value) {
  final d = normalizeAppDate(value);
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
