import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../../core/constants/api_constants.dart';
import '../../core/utils/logger.dart';
import 'process_manager.dart';

/// 统一业务异常（携带中文消息）
class AppException implements Exception {
  AppException(this.message);

  /// 中文错误信息
  final String message;

  @override
  String toString() => message;
}

/// 请求被用户主动取消（区别于网络错误，UI 不应提示失败）
class RequestCancelled implements Exception {
  @override
  String toString() => '请求已取消';
}

/// 长请求的取消句柄：调用 [cancel] 会中止关联请求并使其以 [RequestCancelled] 结束
class RequestHandle {
  bool cancelled = false;
  HttpClientRequest? _request;

  /// 取消关联的请求（幂等）
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _request?.abort();
  }
}

/// 后端 HTTP 服务封装：动态端口 baseUrl、统一请求方法与错误解析
class BackendService extends GetxService {
  BackendService({required ProcessManager processManager})
      : _processManager = processManager;

  final ProcessManager _processManager;

  final HttpClient _client = HttpClient();

  /// 动态 baseUrl：http://127.0.0.1:{port}
  String get baseUrl {
    final port = _processManager.port.value;
    if (port == null) {
      throw AppException('后端服务尚未就绪');
    }
    return 'http://${ApiConstants.localHost}:$port';
  }

  /// GET 请求
  Future<dynamic> get(String path, {Map<String, String>? queryParameters}) {
    return _request('GET', path, queryParameters: queryParameters);
  }

  /// POST 请求（[handle] 用于长请求的中途取消，如聊天生成）
  Future<dynamic> post(String path,
      {Map<String, dynamic>? body, Duration? timeout, RequestHandle? handle}) {
    return _request('POST', path, body: body, timeout: timeout, handle: handle);
  }

  /// PUT 请求
  Future<dynamic> put(String path, {Map<String, dynamic>? body}) {
    return _request('PUT', path, body: body);
  }

  /// DELETE 请求
  Future<dynamic> delete(String path) {
    return _request('DELETE', path);
  }

  /// 统一请求入口
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    Duration? timeout,
    RequestHandle? handle,
  }) async {
    final effectiveTimeout = timeout ?? ApiConstants.defaultTimeout;
    final uri = Uri.parse(baseUrl + path).replace(
      queryParameters: queryParameters?.isEmpty == true ? null : queryParameters,
    );

    try {
      final request = await _client.openUrl(method, uri).timeout(effectiveTimeout);
      // 挂载取消句柄：外部调用 handle.cancel() 即可中止本次请求
      if (handle != null) {
        if (handle.cancelled) {
          request.abort();
          throw RequestCancelled();
        }
        handle._request = request;
      }
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response =
          await request.close().timeout(effectiveTimeout);
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (text.isEmpty) return <String, dynamic>{};
        return jsonDecode(text);
      }

      // 错误响应统一 {"detail":"中文错误信息"}，detail 优先
      throw _parseError(response.statusCode, text);
    } on RequestCancelled {
      rethrow;
    } on SocketException catch (e) {
      // 主动取消时 abort 表现为 SocketException，转换为取消语义
      if (handle?.cancelled == true) throw RequestCancelled();
      Logger.w('网络异常: $e');
      throw AppException('无法连接后端服务，请确认服务正在运行');
    } on TimeoutException {
      Logger.w('请求超时: $method $path');
      throw AppException('请求超时，请稍后重试');
    } on HttpException catch (e) {
      if (handle?.cancelled == true) throw RequestCancelled();
      Logger.w('HTTP 异常: $e');
      throw AppException('网络请求异常，请稍后重试');
    } on AppException {
      rethrow;
    } catch (e) {
      if (handle?.cancelled == true) throw RequestCancelled();
      Logger.e('请求失败: $method $path', e);
      throw AppException('请求失败，请稍后重试');
    }
  }

  /// 解析后端错误响应（detail 优先）
  AppException _parseError(int statusCode, String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic> && data['detail'] != null) {
        return AppException(data['detail'].toString());
      }
    } catch (_) {
      // 忽略解析失败，走默认提示
    }
    switch (statusCode) {
      case 400:
        return AppException('请求参数不合法');
      case 404:
        return AppException('资源不存在');
      default:
        return AppException('服务异常（HTTP $statusCode）');
    }
  }

  @override
  void onClose() {
    _client.close(force: true);
    super.onClose();
  }
}
