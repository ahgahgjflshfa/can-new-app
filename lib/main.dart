import 'package:flutter/material.dart';

import 'app.dart';
import 'services/can_api_client.dart';
import 'services/charge_api_client.dart';
import 'services/limabang_api_client.dart';
import 'services/push_notification_service.dart';
import 'services/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final limabangApi = LimabangApiClient();
  final canApi = CanApiClient();
  final chargeApi = ChargeApiClient();
  final sessionStore = SecureSessionStore();
  final initialLimabangSession = await sessionStore.loadSession();
  if (initialLimabangSession != null) {
    limabangApi.restoreToken(initialLimabangSession.token);
  }
  final initialCanSession = await sessionStore.loadCanSession();
  if (initialCanSession != null) {
    canApi.restoreToken(initialCanSession.token);
  }
  final initialChargeSession = await sessionStore.loadChargeSession();
  if (initialChargeSession != null) {
    chargeApi.restoreToken(initialChargeSession.token);
  }
  final pushService = PushNotificationService();
  await pushService.initialize();
  runApp(
    MyApp(
      limabangApi: limabangApi,
      canApi: canApi,
      chargeApi: chargeApi,
      pushService: pushService,
      sessionStore: sessionStore,
      initialLimabangSession: initialLimabangSession,
      initialCanSession: initialCanSession,
      initialChargeSession: initialChargeSession,
    ),
  );
}
