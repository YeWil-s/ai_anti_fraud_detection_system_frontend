import 'package:ai_anti_fraud_detection_system_frontend/utils/DioRequest.dart';

/// 家庭组管理服务
/// 
/// 功能：
/// 1. 创建家庭组
/// 2. 申请加入家庭组
/// 3. 查看待审批申请列表（管理员）
/// 4. 审批申请（管理员）
class FamilyService {
  static final FamilyService _instance = FamilyService._internal();
  factory FamilyService() => _instance;
  FamilyService._internal();

  /// 创建家庭组
  /// 
  /// [name] 家庭组名称
  /// 
  /// 返回：
  /// ```json
  /// {
  ///   "family_id": 1,
  ///   "group_name": "我的家庭"
  /// }
  /// ```
  Future<Map<String, dynamic>?> createFamily(String name) async {
    try {
      print('🏠 创建家庭组: $name');
      
      // 将查询参数拼接到 URL 中
      final encodedName = Uri.encodeComponent(name);
      final response = await dioRequest.post(
        '/api/family/create?name=$encodedName',
      );

      if (response != null && response['code'] == 200) {
        print('✅ 家庭组创建成功: ${response['data']}');
        return response['data'];
      }

      return null;
    } catch (e) {
      print('❌ 创建家庭组失败: $e');
      rethrow;
    }
  }

  /// 申请加入家庭组
  /// 
  /// [familyId] 家庭组ID
  /// 
  /// 返回：成功返回 true，失败返回 false
  Future<bool> applyToJoin(int familyId) async {
    try {
      print('📝 申请加入家庭组: $familyId');
      
      final response = await dioRequest.post(
        '/api/family/$familyId/apply',
      );

      if (response != null && response['code'] == 200) {
        print('✅ 申请已发送: ${response['message']}');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ 申请加入失败: $e');
      rethrow;
    }
  }

  /// 获取待审批申请列表（管理员专用）
  /// 
  /// 返回：
  /// ```json
  /// [
  ///   {
  ///     "application_id": 1,
  ///     "user_id": 5,
  ///     "phone": "13800138000",
  ///     "apply_time": "2026-03-03 10:30:00"
  ///   }
  /// ]
  /// ```
  Future<List<Map<String, dynamic>>> getApplications() async {
    try {
      print('📋 获取待审批申请列表');
      
      final response = await dioRequest.get('/api/family/applications');

      if (response != null && response['code'] == 200) {
        // 后端返回格式: {data: {items: []}}
        final responseData = response['data'];
        if (responseData is Map && responseData.containsKey('items')) {
          final items = responseData['items'] as List;
          print('✅ 获取成功，共 ${items.length} 条申请');
          return items.cast<Map<String, dynamic>>();
        }
        // 兼容直接返回 List 的情况
        if (responseData is List) {
          print('✅ 获取成功，共 ${responseData.length} 条申请');
          return responseData.cast<Map<String, dynamic>>();
        }
        return [];
      }

      return [];
    } catch (e) {
      print('❌ 获取申请列表失败: $e');
      // 返回空列表而不是抛出异常，避免页面显示错误
      return [];
    }
  }

  /// 审批申请（管理员专用）
  /// 
  /// [appId] 申请记录ID
  /// [isApprove] true=同意，false=拒绝
  /// 
  /// 返回：成功返回 true，失败返回 false
  Future<bool> reviewApplication(int appId, bool isApprove) async {
    try {
      print('⚖️ 审批申请: $appId, ${isApprove ? "同意" : "拒绝"}');
      
      // 将查询参数拼接到 URL 中
      final response = await dioRequest.put(
        '/api/family/applications/$appId?is_approve=$isApprove',
      );

      if (response != null && response['code'] == 200) {
        print('✅ 审批成功: ${response['message']}');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ 审批失败: $e');
      rethrow;
    }
  }

  /// 获取家庭组成员列表
  /// 
  /// 返回：
  /// ```json
  /// [
  ///   {
  ///     "user_id": 1,
  ///     "name": "张三",
  ///     "phone": "13800138000",
  ///     "is_admin": true
  ///   }
  /// ]
  /// ```
  Future<List<Map<String, dynamic>>> getMembers() async {
    try {
      print('👥 获取家庭组成员列表');
      
      final response = await dioRequest.get('/api/family/members');

      print('📦 原始响应: $response');

      if (response != null && response['code'] == 200) {
        final data = response['data'] as List;
        print('✅ 获取成功，共 ${data.length} 个成员');
        print('📋 成员数据: $data');
        return data.cast<Map<String, dynamic>>();
      }

      print('⚠️ 响应格式不正确或code不是200');
      return [];
    } catch (e) {
      print('❌ 获取成员列表失败: $e');
      rethrow;
    }
  }

  /// 退出家庭组
  /// 
  /// 返回：成功返回 true，失败返回 false
  Future<bool> leaveFamily() async {
    try {
      print('🚪 退出家庭组');
      
      final response = await dioRequest.post('/api/family/leave');

      if (response != null && response['code'] == 200) {
        print('✅ 已退出家庭组: ${response['message']}');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ 退出家庭组失败: $e');
      rethrow;
    }
  }

  /// 获取家庭组信息（可选实现）
  /// 
  /// 注：后端文档中未提供此接口，如需要可以让后端添加
  Future<Map<String, dynamic>?> getFamilyInfo() async {
    try {
      print('🏠 获取家庭组信息');
      
      // TODO: 等待后端提供接口
      // final response = await dioRequest.get('/api/family/info');
      
      return null;
    } catch (e) {
      print('❌ 获取家庭组信息失败: $e');
      return null;
    }
  }

  /// 获取我管理的所有家庭组
  /// 
  /// 返回：
  /// ```json
  /// [
  ///   {
  ///     "family_id": 1,
  ///     "group_name": "我的家庭",
  ///     "my_role": "primary",
  ///     "member_count": 3,
  ///     "created_at": "2026-01-01T00:00:00"
  ///   }
  /// ]
  /// ```
  Future<List<Map<String, dynamic>>> getMyAdminFamilies() async {
    try {
      print('👤 获取我管理的家庭组列表');
      
      final response = await dioRequest.get('/api/family/my-admin-families');

      if (response != null && response['code'] == 200) {
        final data = response['data']['items'] as List;
        print('✅ 获取成功，共 ${data.length} 个家庭组');
        return data.cast<Map<String, dynamic>>();
      }

      return [];
    } catch (e) {
      print('❌ 获取管理的家庭组列表失败: $e');
      rethrow;
    }
  }

  /// 获取指定家庭组的成员列表
  /// 
  /// [familyId] 家庭组ID
  Future<List<Map<String, dynamic>>> getMembersByFamilyId(int familyId) async {
    try {
      print('👥 获取家庭组 $familyId 的成员列表');
      
      final response = await dioRequest.get(
        '/api/family/members',
        params: {'family_id': familyId},
      );

      if (response != null && response['code'] == 200) {
        final data = response['data']['members'] as List;
        print('✅ 获取成功，共 ${data.length} 个成员');
        return data.cast<Map<String, dynamic>>();
      }

      return [];
    } catch (e) {
      print('❌ 获取成员列表失败: $e');
      rethrow;
    }
  }
}

