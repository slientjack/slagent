import 'dart:async';

import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/models/message_model.dart';
import '../../../../data/models/workspace_model.dart';
import '../../../../data/repositories/conversation_repository.dart';
import '../../../../data/services/backend_service.dart';
import '../../workspace/controllers/workspace_controller.dart';
import 'permission_controller.dart';

/// 聊天控制器：消息列表、发送（乐观更新）、停止生成、历史加载、清空
class ChatController extends GetxController {
  ChatController({
    required ConversationRepository repository,
    required PermissionController permissionController,
  })  : _repository = repository,
        _permissionController = permissionController;

  final ConversationRepository _repository;

  /// 权限请求轮询（发送期间负责展示授权卡片）
  final PermissionController _permissionController;

  /// 当前发送请求的取消句柄（思考中时非空）
  RequestHandle? _activeHandle;

  /// 正在主动停止（取消请求），catch 时据此静默处理
  bool _stopping = false;

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
    // 发送期间开始监听权限请求（工具越界时会要求用户授权）
    _permissionController.startWatching(ws.id);

    // 乐观追加用户消息
    messages.add(MessageModel(
      id: _uuid.v4(),
      role: 'user',
      content: content,
      timestamp: _nowTimestamp(),
    ));

    try {
      final handle = RequestHandle();
      _activeHandle = handle;
      final result = await _repository.sendMessage(
        message: content,
        workspaceId: ws.id,
        handle: handle,
      );
      messages.add(MessageModel(
        id: _uuid.v4(),
        role: 'assistant',
        content: result.response,
        timestamp: _nowTimestamp(),
        toolCalls: result.toolCalls,
      ));
    } catch (e) {
      // 主动停止：不插入错误气泡，界面静默恢复
      if (_stopping) return;
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
      _stopping = false;
      _activeHandle = null;
      // 回复结束（含失败/超时/停止）后停止权限轮询
      _permissionController.stopWatching();
      isLoading.value = false;
    }
  }

  /// 停止本次生成：中止请求 + 关闭授权卡（未作答请求按拒绝回传）+ 恢复输入状态
  void stop() {
    if (!isLoading.value) return;
    _stopping = true;
    _activeHandle?.cancel();
    // 关闭授权卡并兜底拒绝未决请求，让后端工具线程尽快解锁
    _permissionController.stopWatching();
    isLoading.value = false;
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
    // 停止权限监听（对应后端也会清空该工作区的会话级授权）
    _permissionController.stopWatching();
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
