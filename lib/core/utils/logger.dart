import 'package:flutter/foundation.dart';

/// 简单日志封装（debugPrint 带级别）
class Logger {
  Logger._();

  static const String _tag = '[SLAGENT]';

  /// 调试日志
  static void d(String message) {
    debugPrint('$_tag DEBUG: $message');
  }

  /// 普通信息日志
  static void i(String message) {
    debugPrint('$_tag INFO: $message');
  }

  /// 警告日志
  static void w(String message) {
    debugPrint('$_tag WARN: $message');
  }

  /// 错误日志
  static void e(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('$_tag ERROR: $message');
    if (error != null) {
      debugPrint('$_tag ERROR DETAIL: $error');
    }
    if (stackTrace != null) {
      debugPrint('$_tag ERROR STACK: $stackTrace');
    }
  }
}
