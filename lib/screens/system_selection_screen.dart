import 'package:flutter/material.dart';

import '../models/app_session.dart';
import '../models/can_session.dart';
import '../models/charge_session.dart';
import '../services/charge_api.dart';
import '../services/can_api.dart';
import '../services/limabang_api.dart';
import '../services/push_notification_service.dart';
import '../services/session_store.dart';
import '../theme/app_colors.dart';
import 'can_login_screen.dart';
import 'can_tasks_screen.dart';
import 'charge_login_screen.dart';
import 'charge_tasks_screen.dart';
import 'login_screen.dart';
import 'tasks_screen.dart';

class SystemSelectionScreen extends StatefulWidget {
  const SystemSelectionScreen({
    required this.limabangApi,
    required this.canApi,
    required this.pushService,
    required this.sessionStore,
    this.initialLimabangSession,
    this.initialCanSession,
    this.chargeApi,
    this.initialChargeSession,
    super.key,
  });

  final LimabangApi limabangApi;
  final CanApi canApi;
  final PushNotificationService pushService;
  final SessionStore sessionStore;
  final AppSession? initialLimabangSession;
  final CanSession? initialCanSession;
  final ChargeApi? chargeApi;
  final ChargeSession? initialChargeSession;

  @override
  State<SystemSelectionScreen> createState() => _SystemSelectionScreenState();
}

class _SystemSelectionScreenState extends State<SystemSelectionScreen> {
  var _loading = true;
  int? _handledNavigationSequence;

  @override
  void initState() {
    super.initState();
    _checkSessions();
    widget.pushService.navigationSignal.addListener(
      _handleNotificationNavigation,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationNavigation();
    });
  }

  @override
  void dispose() {
    widget.pushService.navigationSignal.removeListener(
      _handleNotificationNavigation,
    );
    super.dispose();
  }

  void _handleNotificationNavigation() {
    final event = widget.pushService.navigationSignal.value;
    if (!mounted ||
        (event?.system != PushSystem.charge &&
            event?.system != PushSystem.can)) {
      return;
    }
    if (_handledNavigationSequence == event!.sequence) return;
    _handledNavigationSequence = event.sequence;
    if (event.system == PushSystem.can) {
      _enterCan(context);
    } else {
      _enterCharge(context);
    }
  }

  Future<void> _checkSessions() async {
    // Pre-load sessions in background so navigation is faster
    await widget.sessionStore.loadSession();
    await widget.sessionStore.loadCanSession();
    await widget.sessionStore.loadChargeSession();
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.apps, size: 72, color: AppColors.primary),
                  const SizedBox(height: 20),
                  Text(
                    '站務系統',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '請選擇要使用的系統',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 48),
                  if (_loading)
                    const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('正在檢查登入狀態...'),
                        ],
                      ),
                    )
                  else ...[
                    _SystemCard(
                      icon: Icons.accessible_forward,
                      title: '立碼幫幫忙',
                      color: AppColors.primary,
                      onTap: () => _enterLimabang(context),
                    ),
                    const SizedBox(height: 20),
                    _SystemCard(
                      icon: Icons.delete_outline,
                      title: 'Q 潔淨立馬清',
                      color: Colors.green,
                      onTap: () => _enterCan(context),
                    ),
                    const SizedBox(height: 20),
                    _SystemCard(
                      icon: Icons.bolt,
                      title: '無線充故障',
                      color: AppColors.chargePrimary,
                      onTap: () => _enterCharge(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enterLimabang(BuildContext context) async {
    final session = await widget.sessionStore.loadSession();
    if (session != null) {
      widget.limabangApi.restoreToken(session.token);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TasksScreen(
            api: widget.limabangApi,
            user: session.user,
            deviceId: session.deviceId,
            pushService: widget.pushService,
            sessionStore: widget.sessionStore,
          ),
        ),
      );
    } else {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            api: widget.limabangApi,
            pushService: widget.pushService,
            sessionStore: widget.sessionStore,
            deviceId: null,
          ),
        ),
      );
    }
  }

  Future<void> _enterCan(BuildContext context) async {
    final session = await widget.sessionStore.loadCanSession();
    if (session != null) {
      widget.canApi.restoreToken(session.token);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CanTasksScreen(
            api: widget.canApi,
            user: session.user,
            deviceId: session.deviceId,
            pushService: widget.pushService,
            sessionStore: widget.sessionStore,
          ),
        ),
      );
    } else {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CanLoginScreen(
            api: widget.canApi,
            pushService: widget.pushService,
            sessionStore: widget.sessionStore,
            deviceId: null,
          ),
        ),
      );
    }
  }

  Future<void> _enterCharge(BuildContext context) async {
    final api = widget.chargeApi;
    if (api == null) return;
    final session = await widget.sessionStore.loadChargeSession();
    if (session != null) {
      api.restoreToken(session.token);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChargeTasksScreen(
            api: api,
            user: session.user,
            deviceId: session.deviceId,
            pushService: widget.pushService,
            sessionStore: widget.sessionStore,
          ),
        ),
      );
    } else {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChargeLoginScreen(
            api: api,
            pushService: widget.pushService,
            sessionStore: widget.sessionStore,
            deviceId: null,
          ),
        ),
      );
    }
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
