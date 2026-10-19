import 'package:slagent/core/utils/validators.dart';
import 'package:slagent/data/models/message_model.dart';
import 'package:slagent/data/models/settings_model.dart';
import 'package:slagent/data/models/workspace_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators 工作区名称校验', () {
    test('空名称不合法', () {
      expect(Validators.validateWorkspaceName(''), '名称不能为空');
      expect(Validators.validateWorkspaceName('   '), '名称不能为空');
      expect(Validators.validateWorkspaceName(null), '名称不能为空');
    });

    test('包含非法字符不合法', () {
      expect(Validators.validateWorkspaceName('a/b'), isNotNull);
      expect(Validators.validateWorkspaceName('a\\b'), isNotNull);
      expect(Validators.validateWorkspaceName('a:b'), isNotNull);
      expect(Validators.validateWorkspaceName('a*b'), isNotNull);
      expect(Validators.validateWorkspaceName('a?b'), isNotNull);
      expect(Validators.validateWorkspaceName('a<b'), isNotNull);
    });

    test('超长名称不合法', () {
      expect(Validators.validateWorkspaceName('a' * 51), isNotNull);
    });

    test('合法名称通过校验', () {
      expect(Validators.validateWorkspaceName('我的项目'), isNull);
      expect(Validators.validateWorkspaceName('demo-workspace 01'), isNull);
    });
  });

  group('Validators 工作区路径校验', () {
    test('空路径不合法', () {
      expect(Validators.validateWorkspacePath(''), '路径不能为空');
      expect(Validators.validateWorkspacePath(null), '路径不能为空');
    });

    test('相对路径不合法', () {
      expect(Validators.validateWorkspacePath('relative/path'), isNotNull);
    });

    test('Unix / Windows 绝对路径合法', () {
      expect(Validators.validateWorkspacePath('/Users/jack/projects'), isNull);
      expect(Validators.validateWorkspacePath('C:\\Users\\jack'), isNull);
      expect(Validators.validateWorkspacePath('D:/work/demo'), isNull);
    });
  });

  group('WorkspaceModel JSON 序列化', () {
    test('fromJson/toJson 往返一致', () {
      final json = {
        'id': 'w-1',
        'name': '测试工作区',
        'path': '/tmp/demo',
        'createdAt': '2026-10-19T10:00:00',
      };
      final model = WorkspaceModel.fromJson(json);
      expect(model.id, 'w-1');
      expect(model.name, '测试工作区');
      expect(model.path, '/tmp/demo');
      expect(model.createdAt, '2026-10-19T10:00:00');
      expect(model.toJson(), json);
    });

    test('缺失字段时使用安全默认值', () {
      final model = WorkspaceModel.fromJson(<String, dynamic>{});
      expect(model.id, '');
      expect(model.name, '');
      expect(model.path, '');
      expect(model.createdAt, '');
    });
  });

  group('MessageModel JSON 序列化', () {
    test('tool_calls 为 null 时正常解析', () {
      final model = MessageModel.fromJson({
        'id': 'm-1',
        'role': 'user',
        'content': '你好',
        'timestamp': '2026-10-19T10:00:00',
      });
      expect(model.role, 'user');
      expect(model.content, '你好');
      expect(model.toolCalls, isNull);
    });

    test('tool_calls 缺省时正常解析', () {
      final model = MessageModel.fromJson({
        'id': 'm-2',
        'role': 'assistant',
        'content': '在的',
        'timestamp': '2026-10-19T10:00:01',
        'tool_calls': [
          {'tool': 'read_file', 'args': {'path': 'a.txt'}, 'result': '内容'}
        ],
      });
      expect(model.toolCalls, isNotNull);
      expect(model.toolCalls!.length, 1);
      expect(model.toolCalls!.first.tool, 'read_file');
      expect(model.toJson()['tool_calls'], isNotNull);
    });
  });

  group('SettingsModel JSON 解析', () {
    test('解析 GET /api/settings 返回结构', () {
      final model = SettingsModel.fromJson({
        'settings': {
          'model': 'deepseek',
          'temperature': 0.7,
          'max_context_length': 4096,
          'api_key_configured': false,
        },
        'available_models': [
          {'id': 'deepseek', 'name': 'DeepSeek Chat'},
          {'id': 'qwen', 'name': 'Qwen'},
        ],
      });
      expect(model.model, 'deepseek');
      expect(model.temperature, 0.7);
      expect(model.maxContextLength, 4096);
      expect(model.apiKeyConfigured, false);
      expect(model.availableModels.length, 2);
      expect(model.availableModels.first.name, 'DeepSeek Chat');
    });
  });
}
