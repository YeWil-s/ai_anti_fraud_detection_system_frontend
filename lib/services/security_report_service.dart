import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/auth_service.dart';
import 'package:ai_anti_fraud_detection_system_frontend/contants/index.dart';

/// 安全报告服务
/// 
/// 功能：
/// 1. 生成用户安全监测报告（调用大模型）
/// 2. 支持流式输出实时展示
/// 3. 本地缓存报告数据
class SecurityReportService {
  static final SecurityReportService _instance = SecurityReportService._internal();
  factory SecurityReportService() => _instance;
  SecurityReportService._internal();

  static const String _reportCacheKey = 'cached_security_report';
  static const String _reportTimestampKey = 'cached_report_timestamp';
  static const String _reportUserIdKey = 'cached_report_user_id';

  /// 生成用户安全监测报告（非流式）
  /// 
  /// [userId] 用户ID
  /// 
  /// 返回：
  /// ```json
  /// {
  ///   "user_id": 1,
  ///   "username": "zhangsan",
  ///   "report_generated_at": "2026-03-03T14:30:00",
  ///   "report_content": "## 个人反诈安全监测报告\n\n...",
  ///   "stats": { ... }
  /// }
  /// ```
  Future<Map<String, dynamic>?> generateSecurityReport(int userId) async {
    try {
      print('📊 生成安全报告: 用户ID=$userId');

      // 单独为报告生成接口设置 3 分钟超时（大模型生成较慢）
      final dio = Dio();
      dio.options.baseUrl = GlobalConstants.BASE_URL;
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(minutes: 3);
      dio.options.sendTimeout = const Duration(seconds: 30);
      dio.options.headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final token = AuthService().getToken();
      if (token.isNotEmpty) {
        final tokenType = AuthService().getTokenType();
        dio.options.headers['Authorization'] = '$tokenType $token';
      }

      final res = await dio.get('/api/users/$userId/security-report');
      final response = res.data;

      if (response != null) {
        print('✅ 安全报告生成成功');
        print('   用户: ${response['username']}');
        print('   生成时间: ${response['report_generated_at']}');
        print('   报告长度: ${response['report_content']?.length ?? 0} 字符');
        
        // 保存到本地缓存
        await _saveReportToCache(response);
        
        return response;
      }

      return null;
    } catch (e) {
      print('❌ 生成安全报告失败: $e');
      rethrow;
    }
  }

  /// 流式生成安全报告
  /// 
  /// [userId] 用户ID
  /// [onMetadata] 元数据回调（统计数据等）
  /// [onContent] 内容片段回调
  /// [onComplete] 完成回调
  /// [onError] 错误回调
  Future<void> generateSecurityReportStream({
    required int userId,
    required Function(Map<String, dynamic> metadata) onMetadata,
    required Function(String chunk, String fullContent) onContent,
    required Function(Map<String, dynamic> completeData) onComplete,
    required Function(String error) onError,
  }) async {
    try {
      print('📊 开始流式生成安全报告: 用户ID=$userId');

      final dio = Dio();
      dio.options.baseUrl = GlobalConstants.BASE_URL;
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(minutes: 5);
      dio.options.sendTimeout = const Duration(seconds: 30);
      dio.options.headers = {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      };
      dio.options.responseType = ResponseType.stream;
      
      final token = AuthService().getToken();
      if (token.isNotEmpty) {
        final tokenType = AuthService().getTokenType();
        dio.options.headers['Authorization'] = '$tokenType $token';
      }

      final response = await dio.get('/api/users/$userId/security-report?stream=true');
      
      String buffer = '';
      String fullContent = '';
      Map<String, dynamic>? finalData;

      await for (final chunk in response.data.stream) {
        buffer += utf8.decode(chunk);
        
        // 处理 SSE 格式的数据
        while (buffer.contains('\n\n')) {
          final endIndex = buffer.indexOf('\n\n');
          final line = buffer.substring(0, endIndex);
          buffer = buffer.substring(endIndex + 2);
          
          if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6);
            try {
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;
              final type = data['type'] as String;
              
              switch (type) {
                case 'metadata':
                  onMetadata(data['data'] as Map<String, dynamic>);
                  break;
                case 'content':
                  final contentData = data['data'] as Map<String, dynamic>;
                  final chunk = contentData['chunk'] as String;
                  fullContent = contentData['content'] as String;
                  onContent(chunk, fullContent);
                  break;
                case 'complete':
                  finalData = data['data'] as Map<String, dynamic>;
                  // 保存到本地缓存
                  await _saveReportToCache(finalData);
                  onComplete(finalData);
                  break;
              }
            } catch (e) {
              print('⚠️ 解析 SSE 数据失败: $e');
            }
          }
        }
      }
      
      print('✅ 流式报告生成完成');
    } catch (e) {
      print('❌ 流式生成报告失败: $e');
      onError(e.toString());
    }
  }

  /// 获取当前用户的安全报告
  /// 
  /// 需要先从 AuthService 获取当前用户ID
  Future<Map<String, dynamic>?> getCurrentUserReport() async {
    try {
      // 从 AuthService 获取当前用户信息
      final userInfo = AuthService().userInfo;
      
      if (userInfo == null) {
        print('⚠️ 未登录，无法获取报告');
        return null;
      }

      final userId = userInfo['user_id'] as int;
      return await generateSecurityReport(userId);
    } catch (e) {
      print('❌ 获取当前用户报告失败: $e');
      return null;
    }
  }

  /// 从本地缓存获取报告
  /// 
  /// 检查缓存是否有效（7天内）且属于当前用户
  Future<Map<String, dynamic>?> getCachedReport(int currentUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final cachedUserId = prefs.getInt(_reportUserIdKey);
      final cachedTimestamp = prefs.getInt(_reportTimestampKey);
      final cachedReportJson = prefs.getString(_reportCacheKey);
      
      if (cachedUserId == null || cachedTimestamp == null || cachedReportJson == null) {
        return null;
      }
      
      // 检查是否属于当前用户
      if (cachedUserId != currentUserId) {
        print('⚠️ 缓存报告属于其他用户，清空缓存');
        await clearCache();
        return null;
      }
      
      // 检查是否在7天内
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
      final now = DateTime.now();
      final diff = now.difference(cacheTime);
      
      if (diff.inDays > 7) {
        print('⚠️ 缓存报告已过期（超过7天）');
        await clearCache();
        return null;
      }
      
      final report = jsonDecode(cachedReportJson) as Map<String, dynamic>;
      print('✅ 从缓存加载报告，生成时间: ${report['report_generated_at']}');
      return report;
    } catch (e) {
      print('❌ 读取缓存报告失败: $e');
      return null;
    }
  }

  /// 保存报告到本地缓存
  Future<void> _saveReportToCache(Map<String, dynamic> report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = report['user_id'] as int;
      
      await prefs.setInt(_reportUserIdKey, userId);
      await prefs.setInt(_reportTimestampKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(_reportCacheKey, jsonEncode(report));
      
      print('✅ 报告已保存到本地缓存');
    } catch (e) {
      print('❌ 保存报告到缓存失败: $e');
    }
  }

  /// 清空缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_reportUserIdKey);
      await prefs.remove(_reportTimestampKey);
      await prefs.remove(_reportCacheKey);
      print('✅ 报告缓存已清空');
    } catch (e) {
      print('❌ 清空缓存失败: $e');
    }
  }

  /// 检查是否有有效的缓存报告
  Future<bool> hasValidCache(int currentUserId) async {
    final report = await getCachedReport(currentUserId);
    return report != null;
  }
}

