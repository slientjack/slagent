import 'package:get/get.dart';

import '../../core/constants/api_constants.dart';
import '../models/permission_request_model.dart';
import '../services/backend_service.dart';

/// 权限请求数据仓库：拉取待处理请求、提交用户决策
class PermissionRepository extends GetxService {
  PermissionRepository({required BackendService backendService})
      : _backend = backendService;

  final BackendService _backend;

  /// 获取指定工作区当前等待用户决策的请求（按创建时间排序）
  Future<List<PermissionRequestModel>> fetchPending(String workspaceId) async {
    final data = await _backend.get(
      ApiConstants.permissionPending,
      queryParameters: {'workspace_id': workspaceId},
    );
    final list = (data['requests'] as List? ?? []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(PermissionRequestModel.fromJson)
        .toList();
  }

  /// 提交决策：allow_once / allow_session / allow_always / deny
  Future<void> respond(String requestId, String decision) async {
    await _backend.post(ApiConstants.permissionRespond, body: {
      'request_id': requestId,
      'decision': decision,
    });
  }
}
