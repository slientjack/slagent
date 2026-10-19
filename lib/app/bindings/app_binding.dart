import 'package:get/get.dart';

import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/workspace_repository.dart';
import '../../data/services/backend_service.dart';
import '../../data/services/process_manager.dart';
import '../../data/services/storage_service.dart';
import '../../modules/chat/controllers/chat_controller.dart';
import '../../modules/settings/controllers/settings_controller.dart';
import '../../modules/workspace/controllers/workspace_controller.dart';

/// 应用依赖注入：服务立即注册，控制器按需注册
class AppBinding extends Bindings {
  @override
  void dependencies() {
    // ---- 服务层 ----
    // 后端进程管理器（唯一依赖后端的桥）
    final processManager = Get.put(ProcessManager());
    // HTTP 服务（动态端口）
    Get.put(BackendService(processManager: processManager));
    // 本地缓存
    Get.put(StorageService());
    // 数据仓库
    Get.put(WorkspaceRepository(
      backendService: Get.find<BackendService>(),
      storageService: Get.find<StorageService>(),
    ));
    Get.put(ConversationRepository(
      backendService: Get.find<BackendService>(),
    ));

    // ---- 控制器 ----
    // 工作区控制器：立即注册以便启动时先行渲染缓存
    Get.put(WorkspaceController(
      repository: Get.find<WorkspaceRepository>(),
    ));
    // 设置控制器：立即注册（主界面横幅依赖其 apiKeyConfigured 状态）
    Get.put(SettingsController(
      backendService: Get.find<BackendService>(),
    ));
    // 聊天控制器：进入主界面时创建（fenix 保证销毁后可重建）
    Get.lazyPut(
      () => ChatController(
        repository: Get.find<ConversationRepository>(),
      ),
      fenix: true,
    );
  }
}
