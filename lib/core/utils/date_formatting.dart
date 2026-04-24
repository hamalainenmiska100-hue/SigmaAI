import 'package:intl/intl.dart';

class DateFormatting {
  static String short(DateTime dateTime) {
    return DateFormat('MMM d, y • h:mm a').format(dateTime.toLocal());
  }
}
