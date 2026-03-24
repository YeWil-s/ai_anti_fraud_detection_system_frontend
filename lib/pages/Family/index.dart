import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ai_anti_fraud_detection_system_frontend/contants/theme.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/auth_service.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/family_service.dart';
import 'package:ai_anti_fraud_detection_system_frontend/utils/DioRequest.dart';
import 'package:ai_anti_fraud_detection_system_frontend/pages/CallRecords/index.dart';
import 'dart:ui';

// ==================== 主页面：家庭组列表 ====================
class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _myAdminFamilies = [];
  Map<String, dynamic>? _userInfo;
  String? _errorMessage;

  final FamilyService _familyService = FamilyService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 获取当前用户信息
      _userInfo = await _authService.getCurrentUser(forceRefresh: true);
      print('🔍 用户信息: family_id=${_userInfo?['family_id']}');

      // 获取我管理的所有家庭组
      final families = await _familyService.getMyAdminFamilies();
      setState(() {
        _myAdminFamilies = families;
        _isLoading = false;
      });
      print('✅ 加载了 ${_myAdminFamilies.length} 个管理的家庭组');
    } catch (e) {
      print('❌ 加载数据失败: $e');
      setState(() {
        _errorMessage = '加载失败，请稍后重试';
        _isLoading = false;
      });
    }
  }

  /// 创建家庭组
  Future<void> _createFamily() async {
    final nameController = TextEditingController();

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFA9BCBD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text(
          '创建家庭组',
          style: TextStyle(
            color: Color(0xFF0F1923),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '家庭组名称',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF2D4A3E),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: Color(0xFF0F1923), fontSize: 15),
              decoration: InputDecoration(
                hintText: '例如：我的家庭',
                hintStyle: const TextStyle(color: Color(0xFF7A9A9B), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFBFCFD0),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF58A183), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF2D4A3E)),
            child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入家庭组名称'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              try {
                print('📤 正在创建家庭组: ${nameController.text.trim()}');
                final createResult = await _familyService.createFamily(nameController.text.trim());

                if (createResult != null) {
                  print('✅ 家庭组创建成功: $createResult');
                  Navigator.pop(context, createResult);
                }
              } catch (e) {
                print('❌ 创建家庭组失败: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('创建失败: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58A183),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('创建', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      print('🎉 家庭组创建成功，刷新列表');
      _showSuccess('家庭组创建成功！');
      await Future.delayed(Duration(milliseconds: 300));
      await _loadData(forceRefresh: true);
    }
  }

  /// 申请加入家庭组
  Future<void> _joinFamily() async {
    final idController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFA9BCBD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text(
          '加入家庭组',
          style: TextStyle(
            color: Color(0xFF0F1923),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '家庭组ID',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF2D4A3E),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: idController,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Color(0xFF0F1923), fontSize: 15),
              decoration: InputDecoration(
                hintText: '例如：1',
                hintStyle: const TextStyle(color: Color(0xFF7A9A9B), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFBFCFD0),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF58A183), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF58A183).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF58A183).withOpacity(0.4), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF2D4A3E), size: 15),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '申请后需等待管理员审批',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2D4A3E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF2D4A3E)),
            child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (idController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请输入家庭组ID'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              try {
                final familyId = int.parse(idController.text.trim());
                final success = await _familyService.applyToJoin(familyId);
                if (success) {
                  Navigator.pop(context, true);
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('申请失败: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58A183),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('申请', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (result == true) {
      if (mounted) {
        _showSuccess('申请已发送，请等待管理员审批');
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  /// 进入家庭组详情页
  void _enterFamilyDetail(Map<String, dynamic> family) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FamilyDetailPage(family: family),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAF9),
        elevation: 0,
        title: const Text(
          '家庭组管理',
          style: TextStyle(
            color: Color(0xFF0F1923),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF0F1923)),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF58A183)))
          : _errorMessage != null
              ? _buildErrorView()
              : _buildFamilyList(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppTheme.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 80, color: Color(0xFF58A183)),
            SizedBox(height: AppTheme.paddingLarge),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF0F1923),
              ),
            ),
            SizedBox(height: AppTheme.paddingLarge),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF58A183),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.paddingLarge,
                  vertical: AppTheme.paddingMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyList() {
    return Column(
      children: [
        // 顶部操作栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _createFamily,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF58A183),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '创建家庭组',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _joinFamily,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD2E4D6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add, color: Color(0xFF1C3A2F), size: 20),
                        SizedBox(width: 8),
                        Text(
                          '加入家庭组',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C3A2F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 我管理的家庭组列表
        Expanded(
          child: _myAdminFamilies.isEmpty
              ? _buildEmptyFamilyView()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: const Color(0xFF58A183),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _myAdminFamilies.length,
                    itemBuilder: (context, index) {
                      final family = _myAdminFamilies[index];
                      return _buildFamilyCard(family);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyFamilyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.home_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '暂无管理的家庭组',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '创建家庭组或加入已有家庭组',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyCard(Map<String, dynamic> family) {
    final familyName = family['group_name'] ?? '未命名家庭组';
    final memberCount = family['member_count'] ?? 0;
    final myRole = family['my_role'] ?? 'primary';
    final familyId = family['family_id'];

    return GestureDetector(
      onTap: () => _enterFamilyDetail(family),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 家庭组图标
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF58A183).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.family_restroom,
                  color: Color(0xFF58A183),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // 家庭组信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      familyName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F1923),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: myRole == 'primary'
                                ? const Color(0xFF58A183).withOpacity(0.12)
                                : const Color(0xFFD2E4D6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            myRole == 'primary' ? '主管理员' : '副管理员',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: myRole == 'primary'
                                  ? const Color(0xFF58A183)
                                  : const Color(0xFF1C3A2F),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.people_outline, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '$memberCount 人',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 箭头
              const Icon(
                Icons.chevron_right,
                color: Color(0xFFCBD5E1),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 家庭组详情页 ====================
class FamilyDetailPage extends StatefulWidget {
  final Map<String, dynamic> family;

  const FamilyDetailPage({super.key, required this.family});

  @override
  State<FamilyDetailPage> createState() => _FamilyDetailPageState();
}

class _FamilyDetailPageState extends State<FamilyDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FamilyService _familyService = FamilyService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final familyName = widget.family['group_name'] ?? '未命名家庭组';
    final myRole = widget.family['my_role'] ?? 'primary';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAF9),
        elevation: 0,
        title: Text(
          familyName,
          style: const TextStyle(
            color: Color(0xFF0F1923),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF58A183),
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: const Color(0xFF58A183),
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(text: '成员管理'),
            Tab(text: '申请审批'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FamilyMembersTab(
            familyId: widget.family['family_id'],
            familyService: _familyService,
          ),
          FamilyApplicationsTab(
            familyId: widget.family['family_id'],
            familyService: _familyService,
          ),
        ],
      ),
    );
  }
}

// ==================== 成员管理标签页 ====================
class FamilyMembersTab extends StatefulWidget {
  final int familyId;
  final FamilyService familyService;

  const FamilyMembersTab({
    super.key,
    required this.familyId,
    required this.familyService,
  });

  @override
  State<FamilyMembersTab> createState() => _FamilyMembersTabState();
}

class _FamilyMembersTabState extends State<FamilyMembersTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _members = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final members = await widget.familyService.getMembersByFamilyId(widget.familyId);
      setState(() {
        _members = members;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 查看成员的通话记录
  void _viewMemberRecords(Map<String, dynamic> member) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MemberCallRecordsPage(member: member),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF58A183)));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMembers,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF58A183),
                foregroundColor: Colors.white,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_members.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 56, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text('暂无成员', style: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMembers,
      color: const Color(0xFF58A183),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _members.length,
        itemBuilder: (context, index) {
          final member = _members[index];
          final adminRole = member['admin_role'] ?? 'none';
          final isAdmin = adminRole != 'none';

          return GestureDetector(
            onTap: () => _viewMemberRecords(member),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isAdmin
                          ? const Color(0xFF58A183).withOpacity(0.12)
                          : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAdmin ? Icons.shield : Icons.person,
                      color: isAdmin ? const Color(0xFF58A183) : Colors.grey.shade500,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              member['name'] ?? member['username'] ?? '未知用户',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F1923),
                              ),
                            ),
                            if (isAdmin) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: adminRole == 'primary'
                                      ? const Color(0xFF58A183).withOpacity(0.12)
                                      : const Color(0xFFD2E4D6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  adminRole == 'primary' ? '主管理员' : '副管理员',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: adminRole == 'primary'
                                        ? const Color(0xFF58A183)
                                        : const Color(0xFF1C3A2F),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          member['phone'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFCBD5E1),
                    size: 20,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==================== 申请审批标签页 ====================
class FamilyApplicationsTab extends StatefulWidget {
  final int familyId;
  final FamilyService familyService;

  const FamilyApplicationsTab({
    super.key,
    required this.familyId,
    required this.familyService,
  });

  @override
  State<FamilyApplicationsTab> createState() => _FamilyApplicationsTabState();
}

class _FamilyApplicationsTabState extends State<FamilyApplicationsTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _applications = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apps = await widget.familyService.getApplications();
      // 过滤出当前家庭组的申请
      final filteredApps = apps.where((app) => app['family_id'] == widget.familyId).toList();
      setState(() {
        _applications = filteredApps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载失败';
        _isLoading = false;
      });
    }
  }

  Future<void> _reviewApplication(int appId, bool isApprove) async {
    try {
      final success = await widget.familyService.reviewApplication(appId, isApprove);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isApprove ? '已同意申请' : '已拒绝申请'),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadApplications();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF58A183)));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Color(0xFF6B7280))),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadApplications,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF58A183),
                foregroundColor: Colors.white,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_applications.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text('暂无待审批申请', style: TextStyle(fontSize: 15, color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadApplications,
      color: const Color(0xFF58A183),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _applications.length,
        itemBuilder: (context, index) {
          final app = _applications[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person, color: Colors.grey.shade500, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app['phone'] ?? '未知用户',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F1923),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app['apply_time'] ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _reviewApplication(app['application_id'], false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '拒绝',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _reviewApplication(app['application_id'], true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '同意',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF58A183),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==================== 成员通话记录页 ====================
class MemberCallRecordsPage extends StatefulWidget {
  final Map<String, dynamic> member;

  const MemberCallRecordsPage({super.key, required this.member});

  @override
  State<MemberCallRecordsPage> createState() => _MemberCallRecordsPageState();
}

class _MemberCallRecordsPageState extends State<MemberCallRecordsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _records = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = widget.member['user_id'];
      print('📞 加载成员通话记录: userId=$userId');

      // 调用后端接口获取该用户的通话记录
      final response = await dioRequest.get(
        '/api/call-records/my-records',
        params: {'user_id': userId, 'page': 1, 'page_size': 50},
      );

      if (response != null && response['data'] != null) {
        final allRecords = List<Map<String, dynamic>>.from(response['data']['records'] ?? []);
        // 只显示危险或可疑的通话记录
        final riskRecords = allRecords.where((r) {
          final result = r['detected_result'] ?? 'safe';
          return result == 'fake' || result == 'suspicious';
        }).toList();

        setState(() {
          _records = riskRecords;
          _isLoading = false;
        });
        print('✅ 加载了 ${_records.length} 条风险通话记录');
      } else {
        setState(() {
          _records = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ 加载通话记录失败: $e');
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 查看通话详情
  void _viewRecordDetail(Map<String, dynamic> record) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallRecordDetailPage(record: record),
      ),
    );
  }

  String _formatDateTime(String dateTime) {
    try {
      final dt = DateTime.parse(dateTime);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inDays == 0) {
        return '今天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else if (diff.inDays == 1) {
        return '昨天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        return '${dt.month}-${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return dateTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberName = widget.member['name'] ?? widget.member['username'] ?? '未知用户';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAF9),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              memberName,
              style: const TextStyle(
                color: Color(0xFF0F1923),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              '风险通话记录',
              style: TextStyle(
                color: Color(0xFF58A183),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF58A183)))
          : _errorMessage != null
              ? _buildErrorView()
              : _records.isEmpty
                  ? _buildEmptyView()
                  : _buildRecordsList(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadRecords,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58A183),
              foregroundColor: Colors.white,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '暂无风险通话记录',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '该成员近期没有可疑或危险的通话',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    return RefreshIndicator(
      onRefresh: _loadRecords,
      color: const Color(0xFF58A183),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _records.length,
        itemBuilder: (context, index) {
          final record = _records[index];
          final result = record['detected_result'] ?? 'unknown';

          Color resultColor;
          IconData resultIcon;
          String resultText;

          switch (result) {
            case 'fake':
              resultColor = const Color(0xFFDC2626);
              resultIcon = Icons.dangerous;
              resultText = '危险';
              break;
            case 'suspicious':
              resultColor = const Color(0xFFD97706);
              resultIcon = Icons.warning;
              resultText = '可疑';
              break;
            default:
              resultColor = Colors.grey;
              resultIcon = Icons.help_outline;
              resultText = '未知';
          }

          return GestureDetector(
            onTap: () => _viewRecordDetail(record),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: resultColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(resultIcon, color: resultColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record['caller_number'] ?? '未知号码',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F1923),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(record['start_time'] ?? ''),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          if (record['analysis'] != null && record['analysis'].toString().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              record['analysis'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: resultColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        resultText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: resultColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==================== 通话记录详情页 ====================
class CallRecordDetailPage extends StatefulWidget {
  final Map<String, dynamic> record;

  const CallRecordDetailPage({super.key, required this.record});

  @override
  State<CallRecordDetailPage> createState() => _CallRecordDetailPageState();
}

class _CallRecordDetailPageState extends State<CallRecordDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _auditLogs;
  Map<String, dynamic>? _detectionTimeline;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDetailData();
  }

  Future<void> _loadDetailData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final callId = widget.record['call_id'];
      print('📞 加载通话详情: callId=$callId');

      // 并行加载审计日志和检测时间轴
      final results = await Future.wait([
        dioRequest.get('/api/call-records/$callId/audit-logs'),
        dioRequest.get('/api/call-records/$callId/detection-timeline'),
      ]);

      setState(() {
        _auditLogs = results[0]?['data'];
        _detectionTimeline = results[1]?['data'];
        _isLoading = false;
      });
      print('✅ 通话详情加载完成');
    } catch (e) {
      print('❌ 加载通话详情失败: $e');
      setState(() {
        _errorMessage = '加载详情失败: $e';
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(String dateTime) {
    try {
      final dt = DateTime.parse(dateTime);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.record['detected_result'] ?? 'unknown';
    final callerNumber = widget.record['caller_number'] ?? '未知号码';
    final duration = widget.record['duration'] ?? 0;

    Color resultColor;
    String resultText;
    switch (result) {
      case 'fake':
        resultColor = const Color(0xFFDC2626);
        resultText = '危险 - 检测到诈骗';
        break;
      case 'suspicious':
        resultColor = const Color(0xFFD97706);
        resultText = '可疑 - 需要警惕';
        break;
      default:
        resultColor = const Color(0xFF059669);
        resultText = '安全';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAF9),
        elevation: 0,
        title: const Text(
          '通话详情',
          style: TextStyle(
            color: Color(0xFF0F1923),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF58A183)))
          : _errorMessage != null
              ? _buildErrorView()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 基本信息卡片
                      _buildInfoCard(callerNumber, duration, resultColor, resultText),
                      const SizedBox(height: 16),

                      // AI 分析报告
                      if (widget.record['analysis'] != null) ...[
                        _buildSectionTitle('AI 分析报告'),
                        _buildAnalysisCard(widget.record['analysis']),
                        const SizedBox(height: 16),
                      ],

                      // 防骗建议
                      if (widget.record['advice'] != null) ...[
                        _buildSectionTitle('防骗建议'),
                        _buildAdviceCard(widget.record['advice']),
                        const SizedBox(height: 16),
                      ],

                      // 检测时间轴
                      if (_detectionTimeline != null && 
                          _detectionTimeline!['timeline'] != null &&
                          (_detectionTimeline!['timeline'] as List).isNotEmpty) ...[
                        _buildSectionTitle('检测时间轴'),
                        _buildTimelineCard(_detectionTimeline!['timeline']),
                        const SizedBox(height: 16),
                      ],

                      // 审计日志
                      if (_auditLogs != null) ...[
                        if (_auditLogs!['alert_events'] != null && 
                            (_auditLogs!['alert_events'] as List).isNotEmpty) ...[
                          _buildSectionTitle('告警记录'),
                          _buildAlertEventsCard(_auditLogs!['alert_events']),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadDetailData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58A183),
              foregroundColor: Colors.white,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F1923),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String callerNumber, int duration, Color resultColor, String resultText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.phone, color: resultColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      callerNumber,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F1923),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '通话时长: ${duration ~/ 60}分${duration % 60}秒',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: resultColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: resultColor.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                resultText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: resultColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisCard(String analysis) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy, color: const Color(0xFF58A183), size: 20),
              const SizedBox(width: 8),
              const Text(
                'AI 智能分析',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF58A183),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            analysis,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade800,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdviceCard(String advice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF58A183).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: const Color(0xFF058E3C), size: 20),
              const SizedBox(width: 8),
              const Text(
                '防范建议',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF058E3C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            advice,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1B5E20),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(List<dynamic> timeline) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: timeline.map<Widget>((event) {
          final timeOffset = event['time_offset'] ?? 0;
          final overallScore = (event['overall_score'] ?? 0).toDouble();
          final modalities = event['modalities'] ?? {};
          final textConf = (modalities['text']?['confidence'] ?? 0).toDouble();
          final voiceConf = (modalities['voice']?['confidence'] ?? 0).toDouble();
          final videoConf = (modalities['video']?['confidence'] ?? 0).toDouble();
          final detectedText = event['detected_text'] ?? '';
          final keywords = event['detected_keywords'] ?? '';

          Color scoreColor;
          if (overallScore >= 80) {
            scoreColor = const Color(0xFFDC2626);
          } else if (overallScore >= 50) {
            scoreColor = const Color(0xFFD97706);
          } else {
            scoreColor = const Color(0xFF059669);
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '第 ${timeOffset} 秒',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F1923),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scoreColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '风险分: ${overallScore.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scoreColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 三模态置信度
                Row(
                  children: [
                    _buildConfidenceIndicator('文本', textConf, Colors.blue),
                    const SizedBox(width: 12),
                    _buildConfidenceIndicator('语音', voiceConf, Colors.purple),
                    const SizedBox(width: 12),
                    _buildConfidenceIndicator('视频', videoConf, Colors.orange),
                  ],
                ),
                // 检测到的文本
                if (detectedText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '识别文本:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detectedText,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // 关键词
                if (keywords.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD97706).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '敏感关键词:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          keywords,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildConfidenceIndicator(String label, double confidence, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(confidence * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertEventsCard(List<dynamic> events) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: events.map<Widget>((event) {
          final title = event['title'] ?? '系统告警';
          final content = event['content'] ?? '';
          final riskLevel = event['risk_level'] ?? 'medium';

          Color levelColor;
          switch (riskLevel) {
            case 'high':
              levelColor = const Color(0xFFDC2626);
              break;
            case 'medium':
              levelColor = const Color(0xFFD97706);
              break;
            default:
              levelColor = const Color(0xFF059669);
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: levelColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.warning, color: levelColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F1923),
                        ),
                      ),
                      if (content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          content,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
