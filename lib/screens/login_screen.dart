import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_session.dart';
import '../services/api_exception.dart';
import '../services/limabang_api.dart';
import '../services/push_notification_service.dart';
import '../services/session_store.dart';
import '../theme/app_colors.dart';
import '../widgets/snack_bar_message.dart';
import 'tasks_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.api,
    required this.pushService,
    required this.sessionStore,
    required this.deviceId,
    super.key,
  });

  final LimabangApi api;
  final PushNotificationService pushService;
  final SessionStore sessionStore;
  final String? deviceId;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  late final Future<String> _deviceIdFuture;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _deviceIdFuture = widget.deviceId == null
        ? widget.sessionStore.getOrCreateDeviceId()
        : Future.value(widget.deviceId);
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.accessible_forward,
                      size: 72,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '立碼幫幫忙',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '站務任務接單與結案系統',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      key: const Key('accountField'),
                      controller: _accountController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '員工帳號',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '請輸入員工帳號'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('passwordField'),
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '密碼',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? '請輸入密碼' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const Key('loginButton'),
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(_loading ? '登入中...' : '登入'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _loading = true);
    try {
      final deviceId = await _deviceIdFuture;
      final user = await widget.api.login(
        account: _accountController.text.trim(),
        password: _passwordController.text,
        deviceType: Platform.isAndroid ? 'android' : 'windows',
        deviceId: deviceId,
        fcmToken: widget.pushService.fcmToken,
      );
      final token = widget.api.token;
      if (token == null || token.isEmpty) {
        throw const ApiException('登入成功但未取得 Token');
      }
      if (user.stationId != null) {
        await widget.pushService.subscribeToTopic(user.stationId!);
      }
      await widget.sessionStore.saveSession(
        AppSession(token: token, user: user, deviceId: deviceId),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TasksScreen(
            api: widget.api,
            user: user,
            deviceId: deviceId,
            pushService: widget.pushService,
            sessionStore: widget.sessionStore,
          ),
        ),
      );
    } on ApiException catch (error) {
      showSnackBarMessage(context, error.message);
    } on SocketException {
      showSnackBarMessage(context, '無法連線到伺服器，請檢查網路');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}
