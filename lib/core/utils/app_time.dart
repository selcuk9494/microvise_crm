import 'package:intl/intl.dart';

class AppTime {
  static const Duration tzOffset = Duration(hours: 3);

  static DateTime toTr(DateTime dateTime) => dateTime.toUtc().add(tzOffset);

  static DateTime nowUtc() => DateTime.now().toUtc();

  static String formatTr(DateTime dateTime, DateFormat formatter) {
    return formatter.format(toTr(dateTime));
  }
}

