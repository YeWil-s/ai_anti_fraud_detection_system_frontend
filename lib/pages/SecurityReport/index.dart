import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:ai_anti_fraud_detection_system_frontend/contants/theme.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/auth_service.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/security_report_service.dart';
import 'dart:ui';

/// 安全报告页面
/// 
/// 功能：
/// 1. 展示用户通话统计数据（图表形式）
/// 2. 流式生成AI安全报告
/// 3. 本地缓存报告数据
class SecurityReportPage extends StatefulWidget {
  const SecurityReportPage({super.key});

  @override
  State<SecurityReportPage> createState() => _SecurityReportPageState();
}

class _SecurityReportPageState extends State<SecurityReportPage> with SingleTickerProviderStateMixin {
  // 状态管理
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isStreaming = false;
  Map<String, dynamic>? _reportData;
  Map<String, dynamic>? _statsData;
  String? _errorMessage;
  String _streamingContent = '';
  double _generationProgress = 0.0;

  final SecurityReportService _reportService = SecurityReportService();
  final AuthService _authService = AuthService();
  
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    // 检查本地缓存
    _checkCachedReport();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 检查本地缓存的报告
  Future<void> _checkCachedReport() async {
    setState(() => _isLoading = true);
    
    try {
      final userInfo = _authService.userInfo;
      if (userInfo != null) {
        final userId = userInfo['user_id'] as int;
        final cachedReport = await _reportService.getCachedReport(userId);
        
        if (cachedReport != null && mounted) {
          setState(() {
            _reportData = cachedReport;
            _statsData = cachedReport['stats'] as Map<String, dynamic>?;
            _streamingContent = cachedReport['report_content'] ?? '';
            _isLoading = false;
          });
          _showSuccess('已加载上次生成的报告');
          return;
        }
      }
    } catch (e) {
      print('⚠️ 检查缓存失败: $e');
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// 流式生成安全报告
  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
      _isStreaming = true;
      _errorMessage = null;
      _streamingContent = '';
      _generationProgress = 0.0;
    });

    try {
      final userInfo = _authService.userInfo;
      
      if (userInfo == null) {
        _showError('请先登录');
        setState(() {
          _isGenerating = false;
          _isStreaming = false;
        });
        return;
      }

      final userId = userInfo['user_id'] as int;
      
      // 使用流式生成
      await _reportService.generateSecurityReportStream(
        userId: userId,
        onMetadata: (metadata) {
          if (mounted) {
            setState(() {
              _statsData = metadata['stats'] as Map<String, dynamic>?;
            });
          }
        },
        onContent: (chunk, fullContent) {
          if (mounted) {
            setState(() {
              _streamingContent = fullContent;
              _generationProgress = (fullContent.length / 2000).clamp(0.0, 0.95);
            });
            // 自动滚动到底部
            _autoScroll();
          }
        },
        onComplete: (completeData) {
          if (mounted) {
            setState(() {
              _reportData = completeData;
              _statsData = completeData['stats'] as Map<String, dynamic>?;
              _streamingContent = completeData['report_content'] ?? '';
              _isGenerating = false;
              _isStreaming = false;
              _generationProgress = 1.0;
            });
            _showSuccess('报告生成完成！');
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _errorMessage = error;
              _isGenerating = false;
              _isStreaming = false;
            });
            _showError('生成失败: $error');
          }
        },
      );
    } catch (e) {
      print('❌ 生成报告失败: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '生成失败: $e';
          _isGenerating = false;
          _isStreaming = false;
        });
        _showError('生成失败，请检查网络连接');
      }
    }
  }

  /// 自动滚动到内容底部
  void _autoScroll() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// 清空缓存并重新生成
  Future<void> _regenerateReport() async {
    await _reportService.clearCache();
    setState(() {
      _reportData = null;
      _statsData = null;
      _streamingContent = '';
    });
    await _generateReport();
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '安全报告',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_reportData != null)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _regenerateReport,
              tooltip: '重新生成',
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6A1B9A),
              Color(0xFF8E24AA),
              Color(0xFFAB47BC),
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _reportData == null && !_isGenerating
                  ? _buildEmptyView()
                  : _buildReportView(),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.all(50),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.analytics_outlined,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 32),
            
            const Text(
              '智能安全报告',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            
            const SizedBox(height: 12),
            
            Text(
              'AI 分析您的通话记录\n生成个性化防诈骗建议',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.8),
                height: 1.6,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // 功能介绍卡片
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: const Column(
                children: [
                  _FeatureItem(
                    icon: Icons.shield_outlined,
                    title: '综合安全评级',
                    description: '基于近期通话数据的风险评估',
                  ),
                  SizedBox(height: 16),
                  _FeatureItem(
                    icon: Icons.warning_amber_outlined,
                    title: '薄弱点分析',
                    description: '识别您容易上当的诈骗类型',
                  ),
                  SizedBox(height: 16),
                  _FeatureItem(
                    icon: Icons.lightbulb_outline,
                    title: '专属防骗建议',
                    description: '根据您的角色定制防范措施',
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // 生成报告按钮
            _buildGenerateButton(),
            
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[300], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [Color(0xFF00F5A0), Color(0xFF00D9F5)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F5A0).withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _generateReport,
          borderRadius: BorderRadius.circular(32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 28, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  '生成报告',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportView() {
    return Column(
      children: [
        // 统计数据卡片
        if (_statsData != null) _buildStatsCard(),
        
        // 生成进度条
        if (_isGenerating) _buildProgressBar(),
        
        // 报告内容
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 报告头部信息
                    _buildReportHeader(),
                    const Divider(height: 32),
                    // Markdown 内容
                    MarkdownBody(
                      data: _streamingContent.isNotEmpty 
                          ? _streamingContent 
                          : '# 正在生成报告...\n\nAI 正在分析您的通话数据，请稍候。',
                      styleSheet: MarkdownStyleSheet(
                        h1: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF6A1B9A),
                        ),
                        h2: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8E24AA),
                        ),
                        h3: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFAB47BC),
                        ),
                        p: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade800,
                          height: 1.7,
                        ),
                        listBullet: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF6A1B9A),
                        ),
                        strong: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6A1B9A),
                        ),
                        em: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade600,
                        ),
                        blockquote: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                          decoration: TextDecoration.none,
                        ),
                        code: TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          backgroundColor: Colors.grey.shade100,
                        ),
                      ),
                    ),
                    // 打字光标效果
                    if (_isStreaming)
                      Container(
                        width: 8,
                        height: 20,
                        margin: const EdgeInsets.only(top: 4),
                        color: const Color(0xFF6A1B9A),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildStatsCard() {
    final totalCalls = _statsData!['total_calls'] ?? 0;
    final riskCalls = _statsData!['risk_calls'] ?? 0;
    final safeCalls = _statsData!['safe_calls'] ?? 0;
    final riskRate = _statsData!['risk_rate'] ?? 0.0;
    final fakeCalls = _statsData!['fake_calls'] ?? 0;
    final suspiciousCalls = _statsData!['suspicious_calls'] ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Icon(Icons.analytics, color: Colors.white.withOpacity(0.9), size: 20),
              const SizedBox(width: 8),
              Text(
                '通话数据概览',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 统计数字行
          Row(
            children: [
              _buildStatItem('总通话', totalCalls.toString(), Colors.white),
              _buildStatDivider(),
              _buildStatItem('安全', safeCalls.toString(), const Color(0xFF00F5A0)),
              _buildStatDivider(),
              _buildStatItem('风险', riskCalls.toString(), const Color(0xFFFFB74D)),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 风险率进度条
          if (totalCalls > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: riskRate / 100,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        riskRate > 20 ? const Color(0xFFFF6B6B) : const Color(0xFF00F5A0),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${riskRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '风险通话占比',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
          
          // 风险类型分布
          if (fakeCalls > 0 || suspiciousCalls > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (fakeCalls > 0)
                  Expanded(
                    child: _buildRiskTypeBadge(
                      '危险',
                      fakeCalls.toString(),
                      const Color(0xFFFF6B6B),
                    ),
                  ),
                if (fakeCalls > 0 && suspiciousCalls > 0)
                  const SizedBox(width: 8),
                if (suspiciousCalls > 0)
                  Expanded(
                    child: _buildRiskTypeBadge(
                      '可疑',
                      suspiciousCalls.toString(),
                      const Color(0xFFFFB74D),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 40,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white.withOpacity(0.2),
    );
  }

  Widget _buildRiskTypeBadge(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.9)),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'AI 正在生成报告...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _generationProgress,
              backgroundColor: Colors.white.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.9)),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportHeader() {
    final username = _reportData?['username'] ?? _authService.userInfo?['username'] ?? '未知用户';
    final generatedAt = _reportData?['report_generated_at'] ?? '';
    
    String formattedDate = '';
    if (generatedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(generatedAt);
        formattedDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (e) {
        formattedDate = generatedAt;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6A1B9A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person,
                color: Color(0xFF6A1B9A),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1923),
                    ),
                  ),
                  if (formattedDate.isNotEmpty)
                    Text(
                      '报告生成日期: $formattedDate',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 功能介绍项组件
class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}




