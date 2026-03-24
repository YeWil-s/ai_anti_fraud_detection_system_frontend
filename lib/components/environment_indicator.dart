import 'package:flutter/material.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/detection_task_manager.dart';

/// 环境指示器组件
/// 
/// 显示当前通话环境、平台、启用的检测模态
class EnvironmentIndicator extends StatelessWidget {
  final EnvironmentInfo? environment;
  final VoidCallback? onTap;

  const EnvironmentIndicator({
    Key? key,
    this.environment,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (environment == null) {
      return _buildUnknownEnvironment();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _getEnvironmentColor().withOpacity(0.15),
              _getEnvironmentColor().withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _getEnvironmentColor().withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：平台图标 + 环境描述
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getEnvironmentColor().withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getPlatformIcon(),
                    color: _getEnvironmentColor(),
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        environment!.description,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F1923),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '平台: ${_getPlatformDisplayName()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // 状态指示器
                _buildStatusIndicator(),
              ],
            ),
            
            // 分隔线
            if (environment!.isTextChat) ...[
              SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade300),
              SizedBox(height: 12),
              // 聊天双方信息
              _buildChatSpeakers(),
            ],
            
            // 启用的检测模态
            SizedBox(height: 12),
            _buildActiveModalities(),
          ],
        ),
      ),
    );
  }

  /// 未知环境显示
  Widget _buildUnknownEnvironment() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.device_unknown, color: Colors.grey.shade500),
          SizedBox(width: 12),
          Text(
            '正在识别通话环境...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  /// 状态指示器
  Widget _buildStatusIndicator() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getEnvironmentColor().withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _getEnvironmentColor(),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 4),
          Text(
            '检测中',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _getEnvironmentColor(),
            ),
          ),
        ],
      ),
    );
  }

  /// 聊天双方信息
  Widget _buildChatSpeakers() {
    final speakers = environment!.chatSpeakers;
    if (speakers == null) return SizedBox.shrink();

    final userName = speakers['user'] ?? '我';
    final otherName = speakers['other'] ?? '对方';

    return Row(
      children: [
        // 用户（被保护对象）
        Expanded(
          child: _buildSpeakerCard(
            name: userName,
            isUser: true,
            color: Color(0xFF58A183),
          ),
        ),
        SizedBox(width: 8),
        Icon(Icons.swap_horiz, color: Colors.grey.shade400, size: 20),
        SizedBox(width: 8),
        // 对方（可疑对象）
        Expanded(
          child: _buildSpeakerCard(
            name: otherName,
            isUser: false,
            color: Color(0xFFE07A5F),
          ),
        ),
      ],
    );
  }

  /// 聊天者卡片
  Widget _buildSpeakerCard({
    required String name,
    required bool isUser,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUser ? Icons.person : Icons.person_outline,
            color: color,
            size: 16,
          ),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 启用的检测模态
  Widget _buildActiveModalities() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: environment!.activeTasks.map((task) {
        return _buildModalityChip(task);
      }).toList(),
    );
  }

  /// 模态芯片
  Widget _buildModalityChip(DetectionTaskType task) {
    final icon = _getTaskIcon(task);
    final label = _getTaskLabel(task);
    final weight = environment!.weights[task.name.toLowerCase()] ?? 0.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Color(0xFF58A183)),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F1923),
            ),
          ),
          if (weight > 0) ...[
            SizedBox(width: 4),
            Text(
              '${(weight * 100).toInt()}%',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 获取环境颜色
  Color _getEnvironmentColor() {
    switch (environment!.environment) {
      case CallEnvironment.textChat:
        return Color(0xFF07C160); // 微信绿
      case CallEnvironment.voiceChat:
        return Color(0xFF12B7F5); // QQ蓝
      case CallEnvironment.phoneCall:
        return Color(0xFF2196F3); // 电话蓝
      case CallEnvironment.videoCall:
        return Color(0xFF9C27B0); // 视频紫
      default:
        return Colors.grey;
    }
  }

  /// 获取平台图标
  IconData _getPlatformIcon() {
    switch (environment!.platform) {
      case 'wechat':
        return Icons.chat;
      case 'qq':
        return Icons.chat_bubble;
      case 'phone':
        return Icons.phone;
      case 'video_call':
        return Icons.video_call;
      default:
        return Icons.device_unknown;
    }
  }

  /// 获取平台显示名称
  String _getPlatformDisplayName() {
    switch (environment!.platform) {
      case 'wechat':
        return '微信';
      case 'qq':
        return 'QQ';
      case 'phone':
        return '电话';
      case 'video_call':
        return '视频通话';
      default:
        return '未知';
    }
  }

  /// 获取任务图标
  IconData _getTaskIcon(DetectionTaskType task) {
    switch (task) {
      case DetectionTaskType.audio:
        return Icons.mic;
      case DetectionTaskType.video:
        return Icons.videocam;
      case DetectionTaskType.text:
        return Icons.text_fields;
      case DetectionTaskType.screenshot:
        return Icons.screenshot;
    }
  }

  /// 获取任务标签
  String _getTaskLabel(DetectionTaskType task) {
    switch (task) {
      case DetectionTaskType.audio:
        return '音频检测';
      case DetectionTaskType.video:
        return '视频检测';
      case DetectionTaskType.text:
        return '文本检测';
      case DetectionTaskType.screenshot:
        return '截图OCR';
    }
  }
}

/// 聊天消息气泡组件（区分双方）
class ChatMessageBubble extends StatelessWidget {
  final String sender;
  final String content;
  final bool isCurrentUser;
  final DateTime? timestamp;
  final bool isSuspicious;

  const ChatMessageBubble({
    Key? key,
    required this.sender,
    required this.content,
    required this.isCurrentUser,
    this.timestamp,
    this.isSuspicious = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isCurrentUser ? 64 : 16,
          right: isCurrentUser ? 16 : 64,
          bottom: 8,
        ),
        child: Column(
          crossAxisAlignment: isCurrentUser 
              ? CrossAxisAlignment.end 
              : CrossAxisAlignment.start,
          children: [
            // 发送者名称
            if (!isCurrentUser)
              Padding(
                padding: EdgeInsets.only(left: 12, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      sender,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSuspicious 
                            ? Color(0xFFE07A5F) 
                            : Colors.grey.shade600,
                      ),
                    ),
                    if (isSuspicious) ...[
                      SizedBox(width: 4),
                      Icon(
                        Icons.warning_amber,
                        color: Color(0xFFE07A5F),
                        size: 14,
                      ),
                    ],
                  ],
                ),
              ),
            
            // 消息气泡
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isCurrentUser 
                    ? Color(0xFF95EC69) // 微信绿色（发送）
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isCurrentUser ? 16 : 4),
                  topRight: Radius.circular(isCurrentUser ? 4 : 16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: isSuspicious && !isCurrentUser
                    ? Border.all(color: Color(0xFFE07A5F), width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF0F1923),
                  height: 1.5,
                ),
              ),
            ),
            
            // 时间戳
            if (timestamp != null)
              Padding(
                padding: EdgeInsets.only(top: 4, left: 12, right: 12),
                child: Text(
                  _formatTime(timestamp!),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
