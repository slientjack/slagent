import 'package:get/get.dart';

import '../../core/constants/api_constants.dart';
import '../models/message_model.dart';
import '../services/backend_service.dart';

/// 会话数据仓库：聊天历史/清空/发送
class ConversationRepository extends GetxService {
  ConversationRepository({required BackendService backendService})
      : _backend = backendService;

  final BackendService _backend;

  /// 加载指定工作区的聊天历史
  Future<List<MessageModel>> loadHistory(String workspaceId) async {
    final data = await _backend.get(
      ApiConstants.chatHistory,
      queryParameters: {'workspace_id': workspaceId},
    );
    final list = (data['messages'] as List? ?? []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(MessageModel.fromJson)
        .toList();
  }

  /// 清空指定工作区的会话
  Future<void> clearHistory(String workspaceId) async {
    await _backend.post(ApiConstants.chatClear, body: {
      'workspace_id': workspaceId,
    });
  }

  /// 发送消息（LLM 可能较慢，超时 600 秒；[handle] 可用于中途取消）
  Future<({String response, List<ToolCallModel> toolCalls})> sendMessage({
    required String message,
    required String workspaceId,
    double? temperature,
    int? maxContextLength,
    RequestHandle? handle,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'workspace_id': workspaceId,
    };
    final settings = <String, dynamic>{};
    if (temperature != null) settings['temperature'] = temperature;
    if (maxContextLength != null) {
      settings['max_context_length'] = maxContextLength;
    }
    if (settings.isNotEmpty) body['settings'] = settings;

    final data = await _postChat(body, handle);
    final rawToolCalls = data['tool_calls'] as List? ?? [];
    final toolCalls = rawToolCalls
        .whereType<Map<String, dynamic>>()
        .map(ToolCallModel.fromJson)
        .toList();
    return (
      response: data['response']?.toString() ?? '',
      toolCalls: toolCalls,
    );
  }

  /// 发送聊天请求（应用长超时）
  Future<Map<String, dynamic>> _postChat(
    Map<String, dynamic> body,
    RequestHandle? handle,
  ) async {
    final result = await _backend.post(
      ApiConstants.chatSend,
      body: body,
      timeout: ApiConstants.chatTimeout,
      handle: handle,
    );
    if (result is Map<String, dynamic>) return result;
    throw AppException('响应格式错误');
  }
}
