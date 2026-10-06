import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminders.dart';

/// The few things the app needs from the OS notification system. An interface
/// so the scheduling logic can be tested without a device.
abstract class NotificationGateway {
  /// Asks for permission (Android 13+/iOS). True when notifications can be shown.
  Future<bool> requestPermission();
  Future<void> show(int id, String title, String body);
  Future<void> schedule(Reminder reminder);
  Future<void> cancel(int id);
}

class LocalNotificationGateway implements NotificationGateway {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Przypomnienia i alerty',
      channelDescription: 'Odnowienia subskrypcji i przekroczenia budżetów',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<bool> _init() async {
    if (_ready != null) return _ready!;
    try {
      tzdata.initializeTimeZones();
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is requested from the settings switch, not at launch.
          iOS: DarwinInitializationSettings(
              requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
      );
      return _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
      return _ready = false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> show(int id, String title, String body) async {
    if (!await _init()) return;
    await _plugin.show(id: id, title: title, body: body, notificationDetails: _details);
  }

  @override
  Future<void> schedule(Reminder r) async {
    if (!await _init()) return;
    await _plugin.zonedSchedule(
      id: r.id,
      title: r.title,
      body: r.body,
      scheduledDate: tz.TZDateTime.from(r.when, tz.local),
      notificationDetails: _details,
      // Inexact is plenty for a morning reminder and needs no special permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!await _init()) return;
    await _plugin.cancel(id: id);
  }
}
