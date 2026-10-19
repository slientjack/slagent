import 'package:get/get.dart';

import '../../modules/settings/views/settings_view.dart';
import '../../modules/workspace/views/workspace_view.dart';

/// 路由常量
class AppRoutes {
  AppRoutes._();

  /// 主页（工作区 + 聊天）
  static const String home = '/home';

  /// 设置页
  static const String settings = '/settings';
}

/// 路由表
final List<GetPage> appPages = [
  GetPage(
    name: AppRoutes.home,
    page: () => const WorkspaceView(),
    transition: Transition.noTransition,
  ),
  GetPage(
    name: AppRoutes.settings,
    page: () => const SettingsView(),
    transition: Transition.cupertino,
  ),
];
