class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SessionExpiredException extends ApiException {
  const SessionExpiredException() : super('登入狀態已失效，請重新登入');
}
