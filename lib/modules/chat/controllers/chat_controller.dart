import 'dart:async';

import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/models/message_model.dart';
import '../../../../data/models/workspace_model.dart';
import '../../../../data/repositories/conversation_repository.dart';
import '../../workspace/controllers/workspace_controller.dart';

/// 聊天控制器：消息列表、发送（乐观更新）、历史加载、清空
class ChatController extends GetxController {
  ChatController({required ConversationRepository repository})
      : _repository = repository;

  final ConversationRepository _repository;

  /// 消息列表（时间正序：旧 → 新）
  final RxList<MessageModel> messages = <MessageModel>[].obs;

  /// 是否正在等待 AI 回复（发送中）
  final RxBool isLoading = false.obs;

  /// 历史加载中
  final RxBool isHistoryLoading = false.obs;

  /// 错误信息
  final RxnString errorMessage = RxnString();

  final Uuid _uuid = const Uuid();

  /// 当前待重试的错误消息（保留原始用户输入，便于重试）
  final RxnString _lastFailedInput = RxnString();

  Worker? _workspaceWorker;

  @override
  void onInit() {
    super.onInit();
    // 切换工作区时自动加载对应历史
    _workspaceWorker = ever<WorkspaceModel?>(
      Get.find<WorkspaceController>().currentWorkspace,
      (ws) {
        if (ws != null) {
          loadHistory(ws.id);
        } else {
          messages.clear();
        }
      },
    );
    // 初始已选中工作区时直接加载
    final current = Get.find<WorkspaceController>().currentWorkspace.value;
    if (current != null) {
      loadHistory(current.id);
    }
  }

  @override
  void onClose() {
    _workspaceWorker?.dispose();
    super.onClose();
  }

  /// 加载指定工作区的聊天历史
  Future<void> loadHistory(String workspaceId) async {
    isHistoryLoading.value = true;
    errorMessage.value = null;
    try {
      final list = await _repository.loadHistory(workspaceId);
      messages.assignAll(list);
    } catch (e) {
      errorMessage.value = e.toString();
    } finally {
      isHistoryLoading.value = false;
    }
  }

  /// 发送消息：乐观插入用户气泡 → 等待回复；失败插入错误气泡（可重试），不丢用户输入
  Future<void> send(String text) async {
    final content = text.trim();
    final ws = Get.find<WorkspaceController>().currentWorkspace.value;
    if (content.isEmpty || ws == null || isLoading.value) return;

    isLoading.value = true;
    errorMessage.value = null;
    _lastFailedInput.value = null;

    // 乐观追加用户消息
    messages.add(MessageModel(
      id: _uuid.v4(),
      role: 'user',
      content: content,
      timestamp: _nowTimestamp(),
    ));

    try {
      final result = await _repository.sendMessage(
        message: content,
        workspaceId: ws.id,
      );
      messages.add(MessageModel(
        id: _uuid.v4(),
        role: 'assistant',
        content: result.response,
        timestamp: _nowTimestamp(),
        toolCalls: result.toolCalls,
      ));
    } catch (e) {
      // 失败：插入系统错误气泡（红色边框样式，带重试），保留原始输入
      _lastFailedInput.value = content;
      messages.add(MessageModel(
        id: _uuid.v4(),
        role: 'system',
        content: e.toString(),
        timestamp: _nowTimestamp(),
        isError: true,
      ));
    } finally {
      isLoading.value = false;
    }
  }

  /// 重试上一次失败的发送（移除错误气泡后重新发送）
  Future<void> retryLastFailed() async {
    final input = _lastFailedInput.value;
    if (input == null) return;
    // 移除最后一条错误气泡
    if (messages.isNotEmpty && messages.last.isError) {
      messages.removeLast();
    }
    await send(input);
  }

  /// 清空当前工作区会话
  Future<void> clear() async {
    final ws = Get.find<WorkspaceController>().currentWorkspace.value;
    if (ws == null) return;
    errorMessage.value = null;
    try {
      await _repository.clearHistory(ws.id);
      messages.clear();
    } catch (e) {
      errorMessage.value = e.toString();
    }
  }

  /// 当前时间戳（ISO 8601）
  String _nowTimestamp() => DateTime.now().toIso8601String();

  /// 格式化时间戳为 HH:mm（供气泡展示）
  static String formatTime(String timestamp) {
    final dt = DateTime.tryParse(timestamp);
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt);
  }
}
