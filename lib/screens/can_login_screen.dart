import 'dart:io';

import 'package:flutter/material.dart';

import '../models/can_session.dart';
import '../services/api_exception.dart';
import '../services/can_api.dart';
import '../services/push_notification_service.dart';
import '../services/session_store.dart';
import '../widgets/snack_bar_message.dart';
import 'can_tasks_screen.dart';

class CanLoginScreen extends StatefulWidget {
  const CanLoginScreen({
    required this.api,
    required this.pushService,
    required this.sessionStore,
    required this.deviceId,
    super.key,
  });

  final CanApi api;
  final PushNotificationService pushService;
  final SessionStore sessionStore;
  final String? deviceId;

  @override
  State<CanLoginScreen> createState() => _CanLoginScreenState();
}

class _CanLoginScreenState extends State<CanLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  late final Future<String> _deviceIdFuture;
  var _loading = false;
  var _obscurePassword = true;

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
                      Icons.delete_outline,
                      size: 72,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Q 潔淨立馬清',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      key: const Key('canAccountField'),
                      controller: _accountController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '帳號',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '請輸入帳號'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('canPasswordField'),
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '密碼',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '顯示密碼' : '隱藏密碼',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? '請輸入密碼' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('canLoginButton'),
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
      );
      final token = widget.api.token;
      if (token == null || token.isEmpty) {
        throw const ApiException('登入成功但未取得 Token');
      }
      final station = user.station?.trim();
      final topic = user.topic?.trim();
      if (topic != null && topic.isNotEmpty) {
        await widget.pushService.subscribeToTopic(topic);
      } else if (station != null && station.isNotEmpty) {
        await widget.pushService.subscribeToTopic(
          widget.pushService.topicFor(PushSystem.can, station),
        );
      }
      await widget.sessionStore.saveCanSession(
        CanSession(token: token, user: user, deviceId: deviceId),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CanTasksScreen(
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
    } on Object {
      showSnackBarMessage(context, '無法儲存登入狀態，請確認儲存空間後重試');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}
