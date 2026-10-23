import 'tool.dart';

/// The datetime tool: ground truth for "what time is it", deadlines and any
/// date arithmetic the model is asked to do.
///
/// Devices know their zone with certainty; models do not. Reporting the
/// local wall clock next to UTC and the Unix epoch gives the model
/// everything it needs to answer time questions or convert between zones
/// without guessing.
class DatetimeTool extends HalisTool {
  @override
  String get name => 'datetime';

  @override
  String get description =>
      'Get the current date and time on the user\'s device. '
      'Use this whenever an answer depends on today\'s date, the current '
      'time or the weekday — greetings, deadlines, schedules, countdowns — '
      'and before doing any date arithmetic. Returns local time with its '
      'UTC offset, the equivalent UTC time and the Unix epoch.';

  @override
  Map<String, dynamic> get parameters => const {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final now = DateTime.now();
    final buffer = StringBuffer()
      ..writeln('Local : ${_stamp(now)} (${_weekday(now.weekday)})')
      ..writeln('Offset: ${_offset(now)} — device time zone ${now.timeZoneName}')
      ..writeln('UTC   : ${now.toUtc().toIso8601String()}')
      ..writeln('Epoch : ${now.millisecondsSinceEpoch ~/ 1000} seconds');
    return buffer.toString().trim();
  }

  @override
  String labelFor(Map<String, dynamic> args) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '${now.day}/${now.month} $hh:$mm';
  }

  String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _offset(DateTime t) {
    final o = t.timeZoneOffset;
    String two(int v) => v.toString().padLeft(2, '0');
    final sign = o.isNegative ? '-' : '+';
    return '$sign${two(o.inHours)}:${two(o.inMinutes % 60)}';
  }

  String _weekday(int weekday) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][weekday - 1];
}
