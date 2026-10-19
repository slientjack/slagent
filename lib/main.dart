import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/bindings/app_binding.dart';
import 'app/routes/app_routes.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'data/services/process_manager.dart';
import 'modules/settings/controllers/settings_controller.dart';
import 'modules/workspace/controllers/workspace_controller.dart';
import 'shared/widgets/loading_indicator.dart';

void main() {
  runApp(const AiAgentApp());
}

/// 应用根组件
class AiAgentApp extends StatefulWidget {
  const AiAgentApp({super.key});

  @override
  State<AiAgentApp> createState() => _AiAgentAppState();
}

class _AiAgentAppState extends State<AiAgentApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 应用真正退出（detached）时杀掉后端进程，保证 Get.delete 时杀进程
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      Logger.i('应用退出，清理后端进程');
      final pm = Get.isRegistered<ProcessManager>()
          ? Get.find<ProcessManager>()
          : null;
      pm?.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialBinding: AppBinding(),
      getPages: appPages,
      home: const StartupView(),
    );
  }
}

/// 启动页：等待后端就绪的 loading / 错误页（含重启按钮），就绪后进入主界面
class StartupView extends StatefulWidget {
  const StartupView({super.key});

  @override
  State<StartupView> createState() => _StartupViewState();
}

class _StartupViewState extends State<StartupView> {
  Worker? _statusWorker;

  @override
  void initState() {
    super.initState();
    final pm = Get.find<ProcessManager>();
    // 监听后端状态：就绪后加载数据并跳转主界面
    _statusWorker = ever<ProcessManagerStatus>(pm.status, (status) {
      if (status == ProcessManagerStatus.ready) {
        _onBackendReady();
      }
    });
    // 启动后端进程
    pm.start();
  }

  @override
  void dispose() {
    _statusWorker?.dispose();
    super.dispose();
  }

  /// 后端就绪：拉取工作区列表与设置，进入主界面
  void _onBackendReady() {
    Get.find<WorkspaceController>().fetchWorkspaces();
    Get.find<SettingsController>().loadSettings();
    Get.offAllNamed<void>(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final pm = Get.find<ProcessManager>();
    return Scaffold(
      body: Center(
        child: Obx(() {
          switch (pm.status.value) {
            case ProcessManagerStatus.ready:
              // 就绪瞬间即跳转，这里短暂显示加载态
              return const _StartupLoading(message: '正在进入…');
            case ProcessManagerStatus.error:
              return _StartupError(
                message: pm.errorMessage.value ?? '后端服务启动失败',
                onRestart: pm.restart,
              );
            case ProcessManagerStatus.starting:
            case ProcessManagerStatus.idle:
              return const _StartupLoading(message: '正在启动后端服务…');
          }
        }),
      ),
    );
  }
}

/// 启动加载态
class _StartupLoading extends StatelessWidget {
  const _StartupLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppConstants.appName,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        LoadingIndicator(label: message),
      ],
    );
  }
}

/// 启动错误态：显示中文错误 + 重启服务按钮
class _StartupError extends StatelessWidget {
  const _StartupError({required this.message, required this.onRestart});

  final String message;

  final Future<void> Function() onRestart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 56, color: colorScheme.error),
          const SizedBox(height: 16),
          Text('后端服务启动失败',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => onRestart(),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('重启服务'),
          ),
        ],
      ),
    );
  }
}
