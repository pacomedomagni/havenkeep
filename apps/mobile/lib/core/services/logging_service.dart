import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../config/environment_config.dart';

/// Keys that contain sensitive data and must be stripped before logging.
const _kSensitiveKeys = {
  'password',
  'token',
  'accessToken',
  'refreshToken',
  'secret',
  'authorization',
  'cookie',
};

/// Lightweight logging service inspired by Pino.
///
/// Logs are:
/// - Structured JSON for easy parsing
/// - Written to disk for persistence
/// - Optionally shipped to Loki for centralized logging
/// - Minimal overhead (no heavy SDKs)
class LoggingService {
  static LoggingService? _instance;
  static File? _logFile;
  static String? _lokiUrl;
  static bool _initialized = false;

  LoggingService._();

  static Future<void> initialize(EnvironmentConfig config) async {
    if (_initialized) return;

    _instance = LoggingService._();

    // Set up log file
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final logDir = Directory('${dir.path}/logs');
        if (!await logDir.exists()) {
          await logDir.create(recursive: true);
        }

        final timestamp = DateTime.now().toIso8601String().split('T')[0];
        _logFile = File('${logDir.path}/havenkeep-$timestamp.log');
      } catch (e) {
        debugPrint('[LoggingService] Failed to setup log file: $e');
      }
    }

    // Configure Loki endpoint if available
    if (config.enableCrashReporting && config.lokiUrl != null) {
      _lokiUrl = config.lokiUrl;
    }

    _initialized = true;
    _instance!.info('LoggingService initialized', {
      'environment': config.environment.name,
      'lokiEnabled': _lokiUrl != null,
    });
  }

  /// Log at DEBUG level (development only)
  static void debug(String message, [Map<String, dynamic>? context]) {
    if (kDebugMode) {
      _instance?._log(LogLevel.debug, message, context);
    }
  }

  /// Log at INFO level
  static void info(String message, [Map<String, dynamic>? context]) {
    _instance?._log(LogLevel.info, message, context);
  }

  /// Log at WARN level
  static void warn(String message, [Map<String, dynamic>? context]) {
    _instance?._log(LogLevel.warn, message, context);
  }

  /// Log at ERROR level
  static void error(
    String message,
    dynamic error, [
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  ]) {
    _instance?._log(
      LogLevel.error,
      message,
      {
        ...?context,
        'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      },
    );
  }

  /// Log at FATAL level (critical errors)
  static void fatal(
    String message,
    dynamic error, [
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  ]) {
    _instance?._log(
      LogLevel.fatal,
      message,
      {
        ...?context,
        'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      },
    );
  }

  /// Remove sensitive keys from a context map before logging.
  static Map<String, dynamic> _sanitizeContext(Map<String, dynamic> context) {
    final sanitized = <String, dynamic>{};
    for (final entry in context.entries) {
      if (_kSensitiveKeys.contains(entry.key)) {
        sanitized[entry.key] = '[REDACTED]';
      } else if (entry.value is Map<String, dynamic>) {
        sanitized[entry.key] =
            _sanitizeContext(entry.value as Map<String, dynamic>);
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  void _log(LogLevel level, String message, Map<String, dynamic>? context) {
    // Sanitize context before any logging output
    final sanitizedContext =
        context != null && context.isNotEmpty ? _sanitizeContext(context) : context;

    final logEntry = {
      'timestamp': DateTime.now().toIso8601String(),
      'level': level.name.toUpperCase(),
      'message': message,
      'pid': pid,
      if (sanitizedContext != null && sanitizedContext.isNotEmpty)
        'context': sanitizedContext,
    };

    final jsonLog = jsonEncode(logEntry);

    // Write to console (pretty in debug, JSON in release)
    if (kDebugMode) {
      final color = _getColorForLevel(level);
      debugPrint('$color[${level.name.toUpperCase()}] $message${_resetColor()}');
      if (sanitizedContext != null && sanitizedContext.isNotEmpty) {
        debugPrint('  Context: $sanitizedContext');
      }
    } else {
      debugPrint(jsonLog);
    }

    // Write to file
    _writeToFile(jsonLog);

    // Ship to Loki (async, non-blocking)
    if (_lokiUrl != null) {
      _shipToLoki(logEntry);
    }
  }

  void _writeToFile(String jsonLog) {
    if (_logFile != null) {
      try {
        _logFile!.writeAsStringSync('$jsonLog\n', mode: FileMode.append);
      } catch (e) {
        debugPrint('[LoggingService] Failed to write to file: $e');
      }
    }
  }

  void _shipToLoki(Map<String, dynamic> logEntry) {
    // Fire and forget - don't block main thread
    Future.microtask(() async {
      try {
        final payload = {
          'streams': [
            {
              'stream': {
                'app': 'havenkeep',
                'level': logEntry['level'],
              },
              'values': [
                [
                  '${DateTime.now().millisecondsSinceEpoch * 1000000}', // nanoseconds
                  jsonEncode(logEntry),
                ],
              ],
            },
          ],
        };

        await http.post(
          Uri.parse('$_lokiUrl/loki/api/v1/push'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 2));
      } catch (e) {
        // Silently fail - don't want logging to crash the app
        debugPrint('[LoggingService] Failed to ship to Loki: $e');
      }
    });
  }

  String _getColorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '\x1B[36m'; // Cyan
      case LogLevel.info:
        return '\x1B[32m'; // Green
      case LogLevel.warn:
        return '\x1B[33m'; // Yellow
      case LogLevel.error:
        return '\x1B[31m'; // Red
      case LogLevel.fatal:
        return '\x1B[35m'; // Magenta
    }
  }

  String _resetColor() => '\x1B[0m';

  /// Flush all pending logs (call before app exit)
  static Future<void> flush() async {
    // Logs are written synchronously, so nothing to flush
    // But we can ensure the file is closed properly
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Get log file for sharing/debugging
  static File? getLogFile() => _logFile;

  /// Clear old log files (keep last 7 days)
  static Future<void> cleanOldLogs() async {
    if (kIsWeb) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');

      if (!await logDir.exists()) return;

      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final files = await logDir.list().toList();

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          if (stat.modified.isBefore(cutoff)) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('[LoggingService] Failed to clean old logs: $e');
    }
  }
}

enum LogLevel {
  debug,
  info,
  warn,
  error,
  fatal,
}
