import 'dart:io';

import 'package:app_settings/app_settings.dart';

enum NotificationSettingsResult { requested, unsupported, failed }

typedef MobileNotificationSettingsOpener = Future<void> Function();

Future<NotificationSettingsResult> openNotificationSettings({
  bool? isAndroid,
  bool? isIOS,
  MobileNotificationSettingsOpener? opener,
}) async {
  final mobile = (isAndroid ?? Platform.isAndroid) || (isIOS ?? Platform.isIOS);
  if (!mobile) return NotificationSettingsResult.unsupported;
  try {
    await (opener ??
        () =>
            AppSettings.openAppSettings(type: AppSettingsType.notification))();
    return NotificationSettingsResult.requested;
  } on Object {
    return NotificationSettingsResult.failed;
  }
}
