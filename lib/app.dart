import 'package:flutter/material.dart';

import 'models/app_session.dart';
import 'models/can_session.dart';
import 'screens/system_selection_screen.dart';
import 'services/can_api.dart';
import 'services/limabang_api.dart';
import 'services/push_notification_service.dart';
import 'services/session_store.dart';
import 'theme/app_colors.dart';

class MyApp extends StatelessWidget {
  const MyApp({
    required this.limabangApi,
    required this.canApi,
    required this.pushService,
    required this.sessionStore,
    this.initialLimabangSession,
    this.initialCanSession,
    super.key,
  });

  final LimabangApi limabangApi;
  final CanApi canApi;
  final PushNotificationService pushService;
  final SessionStore sessionStore;
  final AppSession? initialLimabangSession;
  final CanSession? initialCanSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '站務系統',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.surface,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    return SystemSelectionScreen(
      limabangApi: limabangApi,
      canApi: canApi,
      pushService: pushService,
      sessionStore: sessionStore,
      initialLimabangSession: initialLimabangSession,
      initialCanSession: initialCanSession,
    );
  }
}
