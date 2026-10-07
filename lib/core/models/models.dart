// =====================================================
// JSON helpers
// =====================================================

/// SQLite flags can arrive as `true`/`false` or `1`/`0`; accept both.
bool asBool(dynamic value, [bool fallback = false]) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true' || value == '1';
  return fallback;
}

int asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

DateTime? parseDate(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  // SQLite timestamps have no timezone and mean UTC ("2026-10-03 03:24:06").
  final hasZone = value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
  return DateTime.tryParse(hasZone ? value : '${value.replaceFirst(' ', 'T')}Z');
}

// =====================================================
// PORTAL USER MODEL
// =====================================================
class PortalUser {
  final int id;
  final String username;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final DateTime createdAt;
  final bool isAdmin;

  PortalUser({
    required this.id,
    required this.username,
    required this.email,
    this.displayName,
    this.avatarUrl,
    required this.createdAt,
    this.isAdmin = false,
  });

  factory PortalUser.fromJson(Map<String, dynamic> json) {
    return PortalUser(
      id: asInt(json['id']),
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      displayName: json['display_name'],
      avatarUrl: json['avatar_url'],
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      isAdmin: asBool(json['is_admin']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'created_at': createdAt.toIso8601String(),
        'is_admin': isAdmin,
      };
}

// =====================================================
// MODERATION RULES MODEL
// =====================================================
class ModerationRule {
  final int? id;
  final int userId;
  final String keyword;
  final String action; // 'mute' | 'kick'
  final bool isActive;
  final DateTime? createdAt;

  ModerationRule({
    this.id,
    required this.userId,
    required this.keyword,
    required this.action,
    this.isActive = true,
    this.createdAt,
  });

  factory ModerationRule.fromJson(Map<String, dynamic> json) {
    return ModerationRule(
      id: json['id'],
      userId: asInt(json['user_id']),
      keyword: json['keyword'] ?? '',
      action: json['action'] ?? 'mute',
      isActive: asBool(json['is_active'], true),
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'keyword': keyword,
        'action': action,
        'is_active': isActive,
      };

  ModerationRule copyWith({
    int? id,
    int? userId,
    String? keyword,
    String? action,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return ModerationRule(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      keyword: keyword ?? this.keyword,
      action: action ?? this.action,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// =====================================================
// AUTO MESSAGE MODEL
// =====================================================
class AutoMessage {
  final int? id;
  final int userId;
  final String content;
  final int sortOrder;
  final bool isActive;
  final DateTime? createdAt;

  AutoMessage({
    this.id,
    required this.userId,
    required this.content,
    required this.sortOrder,
    this.isActive = true,
    this.createdAt,
  });

  factory AutoMessage.fromJson(Map<String, dynamic> json) {
    return AutoMessage(
      id: json['id'],
      userId: asInt(json['user_id']),
      content: json['content'] ?? '',
      sortOrder: asInt(json['sort_order']),
      isActive: asBool(json['is_active'], true),
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'content': content,
        'sort_order': sortOrder,
        'is_active': isActive,
      };

  AutoMessage copyWith({
    int? id,
    int? userId,
    String? content,
    int? sortOrder,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return AutoMessage(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// =====================================================
// BOT SETTINGS MODEL
// =====================================================
class BotSettings {
  /// Lowest interval the backend accepts for recurring messages (seconds).
  static const int minIntervalSeconds = 10;
  static const int maxIntervalSeconds = 3600;

  /// Lowest diamond threshold the backend accepts for immunity.
  static const int minDiamondImmunityThreshold = 50;

  final int? id;
  final int userId;
  final bool autoMessagesEnabled;
  final int messageIntervalSeconds;
  final bool moderationEnabled;
  final bool kickPermanent;
  final bool diamondImmunityEnabled;
  final int diamondImmunityThreshold;

  BotSettings({
    this.id,
    required this.userId,
    this.autoMessagesEnabled = false,
    this.messageIntervalSeconds = 120,
    this.moderationEnabled = true,
    this.kickPermanent = false,
    this.diamondImmunityEnabled = false,
    this.diamondImmunityThreshold = minDiamondImmunityThreshold,
  });

  factory BotSettings.fromJson(Map<String, dynamic> json) {
    return BotSettings(
      id: json['id'],
      userId: asInt(json['user_id']),
      autoMessagesEnabled: asBool(json['auto_messages_enabled']),
      messageIntervalSeconds: asInt(json['message_interval_seconds'], 120),
      moderationEnabled: asBool(json['moderation_enabled'], true),
      kickPermanent: asBool(json['kick_permanent']),
      diamondImmunityEnabled: asBool(json['diamond_immunity_enabled']),
      diamondImmunityThreshold:
          asInt(json['diamond_immunity_threshold'], minDiamondImmunityThreshold),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'auto_messages_enabled': autoMessagesEnabled,
        'message_interval_seconds': messageIntervalSeconds,
        'moderation_enabled': moderationEnabled,
        'kick_permanent': kickPermanent,
        'diamond_immunity_enabled': diamondImmunityEnabled,
        'diamond_immunity_threshold': diamondImmunityThreshold,
      };

  BotSettings copyWith({
    int? id,
    int? userId,
    bool? autoMessagesEnabled,
    int? messageIntervalSeconds,
    bool? moderationEnabled,
    bool? kickPermanent,
    bool? diamondImmunityEnabled,
    int? diamondImmunityThreshold,
  }) {
    return BotSettings(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      autoMessagesEnabled: autoMessagesEnabled ?? this.autoMessagesEnabled,
      messageIntervalSeconds:
          messageIntervalSeconds ?? this.messageIntervalSeconds,
      moderationEnabled: moderationEnabled ?? this.moderationEnabled,
      kickPermanent: kickPermanent ?? this.kickPermanent,
      diamondImmunityEnabled:
          diamondImmunityEnabled ?? this.diamondImmunityEnabled,
      diamondImmunityThreshold:
          diamondImmunityThreshold ?? this.diamondImmunityThreshold,
    );
  }
}

// =====================================================
// ROBOT (SuperLive account + live session), as reported by the backend
// =====================================================

/// The SuperLive account used by the robot. The backend never exposes its token.
class RobotInfo {
  final String? id;
  final String nickname;
  final String? avatar;
  final String authMode; // 'password' | 'token'

  /// The last livestream_id this robot was moderating, if any - lets the UI
  /// offer to resume right away instead of asking for the ID again.
  final String? lastLivestreamId;

  const RobotInfo({
    this.id,
    required this.nickname,
    this.avatar,
    this.authMode = 'password',
    this.lastLivestreamId,
  });

  factory RobotInfo.fromJson(Map<String, dynamic> json) => RobotInfo(
        id: json['id']?.toString(),
        nickname: (json['nickname'] as String?)?.trim().isNotEmpty == true
            ? json['nickname'] as String
            : "Atila's Client",
        avatar: json['avatar'] as String?,
        authMode: json['auth_mode'] as String? ?? 'password',
        lastLivestreamId: json['last_livestream_id'] as String?,
      );
}

/// Result of resolving a creator's public SuperLive id to her current live, if any
/// (`POST /robot/lookup_streamer`). Not being live is a normal result, not an error.
class StreamerLookup {
  final String nickname;
  final String? avatar;
  final bool live;
  final String? livestreamId;

  const StreamerLookup({
    required this.nickname,
    this.avatar,
    required this.live,
    this.livestreamId,
  });

  factory StreamerLookup.fromJson(Map<String, dynamic> json) => StreamerLookup(
        nickname: (json['nickname'] as String?)?.trim().isNotEmpty == true
            ? json['nickname'] as String
            : 'Streamer',
        avatar: json['avatar'] as String?,
        live: json['live'] == true,
        livestreamId: json['livestream_id'] as String?,
      );
}

/// The favourited streamer the robot auto-joins the moment she goes live
/// (`GET`/`PUT /robot/watch`). Persists across reloads and backend restarts.
class StreamerWatch {
  final String? sharedId;
  final String? nickname;
  final String? avatar;
  final bool active;

  const StreamerWatch({
    this.sharedId,
    this.nickname,
    this.avatar,
    this.active = false,
  });

  bool get hasTarget => sharedId != null;

  factory StreamerWatch.fromJson(Map<String, dynamic> json) => StreamerWatch(
        sharedId: json['shared_id'] as String?,
        nickname: json['nickname'] as String?,
        avatar: json['avatar'] as String?,
        active: asBool(json['active']),
      );
}

/// A chat message seen by the robot in the live.
class ChatMessage {
  final String id;
  final String userId;
  final String username;
  final String text;
  final DateTime? timestamp;

  /// 'mute' | 'kick' when a rule was applied to this message.
  final String? action;

  const ChatMessage({
    required this.id,
    required this.userId,
    required this.username,
    required this.text,
    this.timestamp,
    this.action,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        username: json['name']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        timestamp: parseDate(json['ts']),
        action: json['action'] as String?,
      );
}

/// One mute/kick executed (or attempted) by the robot.
class ModerationAction {
  final String id;
  final DateTime? timestamp;
  final String action; // 'mute' | 'kick'
  final String targetName;
  final String keyword;
  final String messageText;
  final bool ok;
  final String? detail;

  const ModerationAction({
    required this.id,
    this.timestamp,
    required this.action,
    required this.targetName,
    required this.keyword,
    required this.messageText,
    required this.ok,
    this.detail,
  });

  factory ModerationAction.fromJson(Map<String, dynamic> json) =>
      ModerationAction(
        id: json['id']?.toString() ?? '',
        timestamp: parseDate(json['ts']),
        action: json['action']?.toString() ?? 'mute',
        targetName: json['target_name']?.toString() ?? '',
        keyword: json['keyword']?.toString() ?? '',
        messageText: json['message_text']?.toString() ?? '',
        ok: asBool(json['ok'], true),
        detail: json['detail'] as String?,
      );
}

/// State of the robot's current (or last) live session.
class RobotSession {
  final bool running;

  /// idle | starting | running | waiting_for_live | stopping | stopped | error
  final String state;

  /// disconnected | connecting | connected
  final String wsState;
  final String? livestreamId;
  final DateTime? startedAt;
  final String? stopReason;
  final String? lastError;
  final int messagesSent;
  final int chatSeen;
  final int actionsOk;
  final int actionsFailed;
  final List<ChatMessage> recentChat; // oldest -> newest
  final List<ModerationAction> recentActions; // oldest -> newest

  const RobotSession({
    this.running = false,
    this.state = 'idle',
    this.wsState = 'disconnected',
    this.livestreamId,
    this.startedAt,
    this.stopReason,
    this.lastError,
    this.messagesSent = 0,
    this.chatSeen = 0,
    this.actionsOk = 0,
    this.actionsFailed = 0,
    this.recentChat = const [],
    this.recentActions = const [],
  });

  factory RobotSession.fromJson(Map<String, dynamic> json) {
    final counters = (json['counters'] as Map?)?.cast<String, dynamic>() ?? {};
    List<T> list<T>(dynamic raw, T Function(Map<String, dynamic>) build) =>
        (raw as List? ?? const [])
            .whereType<Map>()
            .map((e) => build(e.cast<String, dynamic>()))
            .toList();
    return RobotSession(
      running: asBool(json['running']),
      state: json['state'] as String? ?? 'idle',
      wsState: json['ws_state'] as String? ?? 'disconnected',
      livestreamId: json['livestream_id']?.toString(),
      startedAt: parseDate(json['started_at']),
      stopReason: json['stop_reason'] as String?,
      lastError: json['last_error'] as String?,
      messagesSent: asInt(counters['messages_sent']),
      chatSeen: asInt(counters['chat_seen']),
      actionsOk: asInt(counters['actions_ok']),
      actionsFailed: asInt(counters['actions_failed']),
      recentChat: list(json['recent_chat'], ChatMessage.fromJson),
      recentActions: list(json['recent_actions'], ModerationAction.fromJson),
    );
  }
}

/// Response of `GET /robot/status` (and of connect / start / stop).
class RobotStatus {
  final RobotInfo? robot;
  final RobotSession session;
  final int totalActionsOk;
  final int totalActionsFailed;
  final StreamerWatch watch;

  const RobotStatus({
    this.robot,
    this.session = const RobotSession(),
    this.totalActionsOk = 0,
    this.totalActionsFailed = 0,
    this.watch = const StreamerWatch(),
  });

  bool get connected => robot != null;

  factory RobotStatus.fromJson(Map<String, dynamic> json) {
    final robot = json['robot'];
    final totals = (json['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    return RobotStatus(
      robot: robot is Map ? RobotInfo.fromJson(robot.cast<String, dynamic>()) : null,
      session: json['session'] is Map
          ? RobotSession.fromJson((json['session'] as Map).cast<String, dynamic>())
          : const RobotSession(),
      totalActionsOk: asInt(totals['actions_ok']),
      totalActionsFailed: asInt(totals['actions_failed']),
      watch: json['watch'] is Map
          ? StreamerWatch.fromJson((json['watch'] as Map).cast<String, dynamic>())
          : const StreamerWatch(),
    );
  }
}

// =====================================================
// ACCOUNT ACTIVITY (login, rule/message/settings/robot changes)
// =====================================================
class ActivityEntry {
  final int id;
  final String action;
  final String? detail;
  final DateTime? createdAt;

  const ActivityEntry({
    required this.id,
    required this.action,
    this.detail,
    this.createdAt,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
        id: asInt(json['id']),
        action: json['action'] as String? ?? '',
        detail: json['detail'] as String?,
        createdAt: parseDate(json['created_at']),
      );

  /// Human-readable label for [action], in Portuguese, matching the backend's
  /// action strings (see db.log_activity call sites in main.py).
  String get label => switch (action) {
        'login' => 'Login no portal',
        'account_created' => 'Conta criada',
        'rule_created' => 'Palavra de moderação adicionada',
        'rule_updated' => 'Palavra de moderação alterada',
        'rule_deleted' => 'Palavra de moderação removida',
        'message_created' => 'Mensagem automática adicionada',
        'message_updated' => 'Mensagem automática alterada',
        'message_deleted' => 'Mensagem automática removida',
        'settings_updated' => 'Configurações alteradas',
        'robot_connected' => 'Robô conectado',
        'robot_disconnected' => 'Robô desconectado',
        'session_started' => 'Moderação iniciada',
        'session_stopped' => 'Moderação parada',
        'session_auto_started' => 'Moderação iniciada automaticamente',
        'favorite_live_connected' => 'Streamer ao vivo & Robô conectado',
        'live_summary' => 'Resumo da Transmissão',
        'live_ended' => 'Live encerrada',
        'session_switched_live' => 'Live alterada',
        _ => action,
      };
}

// =====================================================
// MODERATION STATS (aggregated server-side from moderation_log)
// =====================================================
class KeywordCount {
  final String keyword;
  final int count;

  KeywordCount({required this.keyword, required this.count});

  factory KeywordCount.fromJson(Map<String, dynamic> json) =>
      KeywordCount(keyword: json['keyword'] ?? '', count: asInt(json['n']));
}

class DayCount {
  final DateTime day;
  final int count;

  DayCount({required this.day, required this.count});

  factory DayCount.fromJson(Map<String, dynamic> json) =>
      DayCount(day: parseDate(json['day']) ?? DateTime.now(), count: asInt(json['n']));
}

class LiveStats {
  final String livestreamId;
  final int count;
  final DateTime? firstAt;
  final DateTime? lastAt;

  LiveStats({
    required this.livestreamId,
    required this.count,
    this.firstAt,
    this.lastAt,
  });

  factory LiveStats.fromJson(Map<String, dynamic> json) => LiveStats(
        livestreamId: json['livestream_id']?.toString() ?? '',
        count: asInt(json['n']),
        firstAt: parseDate(json['first_at']),
        lastAt: parseDate(json['last_at']),
      );
}

class ModerationStats {
  final int days;
  final int totalActions;
  final int mutes;
  final int kicks;
  final double? successRate;
  final List<KeywordCount> topKeywords;
  final List<DayCount> byDay;
  final List<LiveStats> recentLives;

  ModerationStats({
    required this.days,
    required this.totalActions,
    required this.mutes,
    required this.kicks,
    this.successRate,
    this.topKeywords = const [],
    this.byDay = const [],
    this.recentLives = const [],
  });

  factory ModerationStats.fromJson(Map<String, dynamic> json) => ModerationStats(
        days: asInt(json['days'], 30),
        totalActions: asInt(json['total_actions']),
        mutes: asInt(json['mutes']),
        kicks: asInt(json['kicks']),
        successRate: (json['success_rate'] as num?)?.toDouble(),
        topKeywords: (json['top_keywords'] as List? ?? [])
            .map((e) => KeywordCount.fromJson(e))
            .toList(),
        byDay: (json['by_day'] as List? ?? []).map((e) => DayCount.fromJson(e)).toList(),
        recentLives: (json['recent_lives'] as List? ?? [])
            .map((e) => LiveStats.fromJson(e))
            .toList(),
      );
}
