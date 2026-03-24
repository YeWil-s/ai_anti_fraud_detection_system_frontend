import 'package:flutter/material.dart';
import 'package:ai_anti_fraud_detection_system_frontend/contants/theme.dart';
import 'package:ai_anti_fraud_detection_system_frontend/pages/Detection/index.dart';
import 'package:ai_anti_fraud_detection_system_frontend/pages/CallRecords/index.dart';
import 'package:ai_anti_fraud_detection_system_frontend/pages/Family/index.dart';
import 'package:ai_anti_fraud_detection_system_frontend/pages/Profile/index.dart';
import 'package:ai_anti_fraud_detection_system_frontend/pages/Test/index.dart';
import 'package:ai_anti_fraud_detection_system_frontend/utils/PermissionManager.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/RealTimeDetectionService.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/family_alert_manager.dart';
import 'package:ai_anti_fraud_detection_system_frontend/components/floating_alert_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 2;
  final PermissionManager _permissionManager = PermissionManager();
  bool _hasRequestedPermissions = false;
  final GlobalKey<ConvexAppBarState> _barKey = GlobalKey<ConvexAppBarState>();
  
  // ✅ 家庭预警管理器
  final FamilyAlertManager _familyAlertManager = FamilyAlertManager();
  final FloatingAlertManager _floatingAlertManager = FloatingAlertManager();

  void _switchTab(int index) {
    setState(() => _currentIndex = index);
    _barKey.currentState?.animateTo(index);
  }

  List<Widget> get _pages => [
    CallRecordsPage(),
    TestPage(),
    DetectionPage(),
    FamilyPage(),
    ProfilePage(onSwitchTab: _switchTab),
  ];

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
    
    // ✅ 初始化家庭预警监听（延迟初始化，等待 DetectionPage 创建服务）
    Future.delayed(Duration(seconds: 2), () {
      _initFamilyAlertListener();
    });
  }
  
  /// ✅ 初始化家庭预警监听
  void _initFamilyAlertListener() {
    // 获取 DetectionPage 中的服务实例
    // 注意：这里使用了一个全局可访问的方式，实际项目中可以使用 Provider 或 GetIt
    print('🔔 初始化家庭预警监听...');
    
    // 监听家庭预警流
    _familyAlertManager.alertStream.listen((alertData) {
      if (!mounted) return;
      
      print('🚨 MainPage 收到家庭预警，显示警告');
      
      final displayMode = alertData['display_mode'] ?? 'popup';
      final action = alertData['action'] ?? 'none';
      final victimPhone = alertData['victim_phone'];
      
      // 根据显示模式显示不同警告
      if (displayMode == 'fullscreen') {
        // 全屏警告（Level 3）
        _familyAlertManager.showFullScreenAlert(
          context,
          alertData,
          onDismiss: () {
            _floatingAlertManager.hide();
          },
        );
      } else if (displayMode == 'popup') {
        // 弹窗警告（Level 2）
        _familyAlertManager.showPopupAlert(
          context,
          alertData,
          onDismiss: () {
            // 弹窗关闭后显示悬浮窗
            _showFloatingAlert(alertData);
          },
        );
      } else {
        // Toast 提示（Level 1）- 只显示悬浮窗
        _showFloatingAlert(alertData);
      }
    });
  }
  
  /// ✅ 显示悬浮预警
  void _showFloatingAlert(Map<String, dynamic> alertData) {
    final victimPhone = alertData['victim_phone'];
    
    _floatingAlertManager.show(
      context,
      victimName: alertData['victim_name'] ?? '未知',
      victimPhone: victimPhone,
      message: alertData['message'] ?? '',
      riskLevel: alertData['risk_level'] ?? 'high',
      onCall: () {
        if (victimPhone != null) {
          _familyAlertManager.makeEmergencyCall(victimPhone);
        }
      },
      onDismiss: () {
        print('悬浮预警已关闭');
      },
    );
  }

  /// 检查并请求权限（仅首次启动）
  Future<void> _checkAndRequestPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('is_first_launch') ?? true;
    
    if (isFirstLaunch && !_hasRequestedPermissions) {
      _hasRequestedPermissions = true;
      
      // 延迟一下，等待页面完全加载
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        await _permissionManager.requestPermissionsOnFirstLaunch(context);
        await prefs.setBool('is_first_launch', false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ 使用 IndexedStack 保持所有页面存活，切换 tab 时不销毁 Widget
      // 这样 DetectionPage 切换到其他 tab 时不会被 dispose，检测服务不会中断
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: ConvexAppBar(
        key: _barKey,
        style: TabStyle.reactCircle,
        items: [
          TabItem(icon: Icons.history, title: '通话记录'),
          TabItem(icon: Icons.science_outlined, title: '测试'),
          TabItem(icon: Icons.radar, title: '实时监测'),
          TabItem(icon: Icons.family_restroom, title: '家庭组'),
          TabItem(icon: Icons.person_outline, title: '我的'),
        ],
        initialActiveIndex: _currentIndex,
        onTap: (int index) {
            setState(() {
              _currentIndex = index;
            });
          },
        // 墨绿色系配色
        backgroundColor: Color(0xFF1B553E),
        activeColor: Colors.white, // 激活时的图标和文字颜色
        color: Color(0xFF6EE7B7).withOpacity(0.6), // 未激活时的图标和文字颜色（浅绿色半透明）
        gradient: LinearGradient(
          colors: [
            Color(0xFF1B553E),
            Color(0xFF164A35),
          ],
            ),
        height: 60,
        top: -20,
        curveSize: 80,
        elevation: 8,
      ),
    );
  }
}