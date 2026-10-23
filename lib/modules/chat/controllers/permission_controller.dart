import 'dart:async';

import 'package:get/get.dart';

import '../../../core/constants/api_constants.dart';
import '../../../data/models/permission_request_model.dart';
import '../../../data/repositories/permission_repository.dart';
import '../widgets/permission_card.dart';

/// 权限请求控制器：聊天请求进行期间轮询后端待授权列表，
/// 并把请求暴露为 [currentRequest]，由聊天界面在消息列表下方内联展示。
///
/// 为什么轮询：聊天接口是同步阻塞的（工具线程等待用户决策），前端无法在同一次
/// HTTP 请求中接收「需要授权」事件，因此用独立短轮询获取 pending 列表。
class PermissionController extends GetxController {
  PermissionController({required PermissionRepository repository})
      : _repository = repository;

  final PermissionRepository _repository;

  /// 当前等待用户决策的请求（非空时聊天界面显示授权卡片）
  final currentRequest = Rxn<PermissionRequestModel>();

  /// 轮询定时器（仅在发送消息期间运行）
  Timer? _timer;

  /// 当前监听的工作区
  String? _workspaceId;

  /// 防止上一轮轮询未结束时重复发起
  bool _polling = false;

  /// 卡片是否正在展示（同一时间只处理一个请求）
  bool _showing = false;

  /// 已处理过的请求 id，避免重复展示
  final Set<String> _handledIds = <String>{};

  /// 是否正在监听权限请求
  bool get isWatching => _timer != null;

  /// 开始监听指定工作区的权限请求（重复调用不会叠加定时器）
  void startWatching(String workspaceId) {
    if (_workspaceId != workspaceId) {
      // 切换工作区时重置已处理集合
      _handledIds.clear();
      _workspaceId = workspaceId;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(
      ApiConstants.permissionPollInterval,
      (_) => _poll(),
    );
    // 立即拉取一次，缩短首个请求的等待时间
    _poll();
  }

  /// 停止监听；尚未作答的请求按拒绝回传（避免工具线程空等）
  void stopWatching() {
    _timer?.cancel();
    _timer = null;
    _workspaceId = null;
    final pending = currentRequest.value;
    if (pending != null) {
      currentRequest.value = null;
      _showing = false;
      _respondQuietly(pending.id, PermissionCard.deny);
    }
  }

  /// 用户在授权卡片上作出选择后调用（参数为 PermissionCard 决策常量）
  Future<void> submit(String decision) async {
    final req = currentRequest.value;
    if (req == null) return;
    // 立即清空并复位，避免连点重复提交，也让下一轮轮询能处理后续请求
    currentRequest.value = null;
    _showing = false;
    try {
      await _repository.respond(req.id, decision);
    } catch (_) {
      // 提交失败（请求已超时等）静默忽略，后端有超时兜底
    }
  }

  /// 一次轮询：发现未处理的请求就放入 [currentRequest] 交给界面展示
  Future<void> _poll() async {
    if (_polling || _showing) return;
    final workspaceId = _workspaceId;
    if (workspaceId == null) return;

    _polling = true;
    try {
      final requests = await _repository.fetchPending(workspaceId);
      PermissionRequestModel? next;
      for (final item in requests) {
        if (!_handledIds.contains(item.id)) {
          next = item;
          break;
        }
      }
      if (next == null) return;

      _handledIds.add(next.id);
      _showing = true;
      currentRequest.value = next;
    } catch (_) {
      // 轮询失败（后端关闭等）静默忽略，下个周期重试
    } finally {
      _polling = false;
    }
  }

  /// 尽力回传决策但不抛错（停止监听时的兜底拒绝）
  void _respondQuietly(String requestId, String decision) {
    _repository.respond(requestId, decision).catchError((_) {});
  }

  @override
  void onClose() {
    _timer?.cancel();
    _timer = null;
    super.onClose();
  }
}
