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
  final String? displayName;
  final String? avatarUrl;
  final DateTime createdAt;
  final bool isAdmin;

  /// True while the user still holds a temporary password released by the admin:
  /// the app only lets her reach the "set a new password" screen until she does.
  final bool mustChangePassword;

  PortalUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.createdAt,
    this.isAdmin = false,
    this.mustChangePassword = false,
  });

  /// Name to show: the display name when it has text, otherwise the username.
  String get shownName {
    final name = displayName?.trim() ?? '';
    return name.isNotEmpty ? name : username;
  }

  factory PortalUser.fromJson(Map<String, dynamic> json) {
    return PortalUser(
      id: asInt(json['id']),
      username: json['username'] ?? '',
      displayName: json['display_name'],
      avatarUrl: json['avatar_url'],
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      isAdmin: asBool(json['is_admin']),
      mustChangePassword: asBool(json['must_change_password']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'created_at': createdAt.toIso8601String(),
        'is_admin': isAdmin,
        'must_change_password': mustChangePassword,
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

/// Result of POST /moderation/test: whether a sample phrase would trip one
/// of the user's own active rules right now, and which one.
class PhraseTestResult {
  final bool matched;
  final String? action;
  final String? keyword;

  PhraseTestResult({required this.matched, this.action, this.keyword});

  factory PhraseTestResult.fromJson(Map<String, dynamic> json) => PhraseTestResult(
        matched: asBool(json['matched']),
        action: json['action'],
        keyword: json['keyword'],
      );
}

/// Result of POST /moderation/rules/bulk: exactly what landed and what
/// didn't (and why), so a pasted batch's outcome is never a guess.
class BulkSkip {
  final String keyword;
  final String reason;

  BulkSkip({required this.keyword, required this.reason});

  factory BulkSkip.fromJson(Map<String, dynamic> json) =>
      BulkSkip(keyword: json['keyword'] ?? '', reason: json['reason'] ?? '');
}

class BulkRuleResult {
  final List<ModerationRule> created;
  final List<BulkSkip> skipped;

  BulkRuleResult({required this.created, required this.skipped});

  factory BulkRuleResult.fromJson(Map<String, dynamic> json) => BulkRuleResult(
        created: (json['created'] as List? ?? [])
            .map((e) => ModerationRule.fromJson(e))
            .toList(),
        skipped: (json['skipped'] as List? ?? []).map((e) => BulkSkip.fromJson(e)).toList(),
      );
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
  static const int minDiamondImmunityThreshold = 30;

  /// What a creator starts with (the floor was lowered to 30 without changing this).
  static const int defaultDiamondImmunityThreshold = 50;

  final int? id;
  final int userId;
  final bool autoMessagesEnabled;
  final int messageIntervalSeconds;
  final bool moderationEnabled;
  final bool kickPermanent;
  final bool diamondImmunityEnabled;
  final int diamondImmunityThreshold;
  final bool liveRankingEnabled;

  /// Also send that ranking to the streamer by private message (inbox) when the live ends.
  final bool liveRankingDmEnabled;

  BotSettings({
    this.id,
    required this.userId,
    this.autoMessagesEnabled = false,
    this.messageIntervalSeconds = 120,
    this.moderationEnabled = true,
    this.kickPermanent = false,
    this.diamondImmunityEnabled = false,
    this.diamondImmunityThreshold = defaultDiamondImmunityThreshold,
    this.liveRankingEnabled = false,
    this.liveRankingDmEnabled = false,
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
      diamondImmunityThreshold: asInt(
          json['diamond_immunity_threshold'], defaultDiamondImmunityThreshold),
      liveRankingEnabled: asBool(json['live_ranking_enabled']),
      liveRankingDmEnabled: asBool(json['live_ranking_dm_enabled']),
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
        'live_ranking_enabled': liveRankingEnabled,
        'live_ranking_dm_enabled': liveRankingDmEnabled,
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
    bool? liveRankingEnabled,
    bool? liveRankingDmEnabled,
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
      liveRankingEnabled: liveRankingEnabled ?? this.liveRankingEnabled,
      liveRankingDmEnabled: liveRankingDmEnabled ?? this.liveRankingDmEnabled,
    );
  }
}

// =====================================================
// DIAMOND RANKING OF ONE LIVE (written when the live ends)
// =====================================================
class RankingEntry {
  final String name;
  final int diamonds;

  const RankingEntry({required this.name, required this.diamonds});

  factory RankingEntry.fromJson(Map<String, dynamic> json) => RankingEntry(
        name: json['name']?.toString() ?? '?',
        diamonds: asInt(json['diamonds']),
      );
}

class LiveRanking {
  final String livestreamId;
  final DateTime? endedAt;
  final int totalDiamonds;
  final List<RankingEntry> entries;

  /// The same ranking as plain text ("nome: enviou N diamantes"), ready to copy.
  final String text;

  /// What happened to the private message to the streamer (null = not attempted).
  final String? dmStatus;

  const LiveRanking({
    required this.livestreamId,
    required this.endedAt,
    required this.totalDiamonds,
    required this.entries,
    required this.text,
    this.dmStatus,
  });

  factory LiveRanking.fromJson(Map<String, dynamic> json) {
    // the server stores UTC without a zone suffix ("2026-10-21 03:10:00")
    final raw = json['ended_at']?.toString();
    DateTime? ended;
    if (raw != null && raw.isNotEmpty) {
      ended = DateTime.tryParse(raw.contains('T') ? raw : raw.replaceFirst(' ', 'T'));
      if (ended != null && !raw.endsWith('Z') && !raw.contains('+')) {
        ended = DateTime.utc(ended.year, ended.month, ended.day, ended.hour,
            ended.minute, ended.second);
      }
    }
    return LiveRanking(
      livestreamId: json['livestream_id']?.toString() ?? '',
      endedAt: ended,
      totalDiamonds: asInt(json['total_diamonds']),
      entries: [
        for (final e in (json['entries'] as List? ?? const []).whereType<Map>())
          RankingEntry.fromJson(e.cast<String, dynamic>())
      ],
      text: json['text']?.toString() ?? '',
      dmStatus: json['dm_status']?.toString(),
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
  final String authMode; // 'password' | 'phone' | 'email_code' | 'token'

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

  /// Non-null only while [state] is 'stopped' AND the robot is still favourited
  /// on this same streamer: the watch loop found her live, but still under the
  /// exact livestream_id this session was stopped on, so it's deliberately not
  /// auto-restarting yet (see backend WatchManager) - waiting for a genuinely
  /// new id, not stuck/broken. How long that's been true, in seconds.
  final double? watchWaitingSeconds;
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
    this.watchWaitingSeconds,
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
      watchWaitingSeconds: (json['watch_waiting_seconds'] as num?)?.toDouble(),
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
        'live_ranking' => 'Ranking de diamantes da live',
        'live_ranking_dm' => 'Ranking enviado por mensagem privada',
        'live_ended' => 'Live encerrada',
        'session_switched_live' => 'Live alterada',
        'watch_stuck' => 'Aguardando nova transmissão',
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

/// ===== ADMIN PANEL MODELS =====
/// Only ever populated for an is_admin account (GET /admin/*) - see
/// AdminProvider. Deliberately cross-user; never used anywhere else.

class AdminRobotInfo {
  final String? nickname;
  final String? authMode;
  const AdminRobotInfo({this.nickname, this.authMode});

  factory AdminRobotInfo.fromJson(Map<String, dynamic> json) => AdminRobotInfo(
        nickname: json['nickname'] as String?,
        authMode: json['auth_mode'] as String?,
      );
}

class AdminUserSummary {
  final int id;
  final String username;
  final String? displayName;
  final bool isAdmin;
  final bool mustChangePassword; // an admin released a reset and she hasn't set her own yet
  final DateTime? createdAt;
  final AdminRobotInfo? robot;

  /// 'não configurado' | 'conectado (parado)' | 'aguardando' | 'ativo' | 'erro'
  final String robotStatus;
  final String? sessionState;
  final String? sessionLivestreamId;
  final bool watchActive;
  final String? watchNickname;
  final int rulesCount;
  final int messagesCount;
  final int? agencyId;
  final String? agencyName;

  const AdminUserSummary({
    required this.id,
    required this.username,
    this.displayName,
    this.isAdmin = false,
    this.mustChangePassword = false,
    this.createdAt,
    this.robot,
    this.robotStatus = 'não configurado',
    this.sessionState,
    this.sessionLivestreamId,
    this.watchActive = false,
    this.watchNickname,
    this.rulesCount = 0,
    this.messagesCount = 0,
    this.agencyId,
    this.agencyName,
  });

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) => AdminUserSummary(
        id: asInt(json['id']),
        username: json['username'] as String? ?? '',
        displayName: json['display_name'] as String?,
        isAdmin: asBool(json['is_admin']),
        mustChangePassword: asBool(json['must_change_password']),
        createdAt: parseDate(json['created_at']),
        robot: json['robot'] is Map
            ? AdminRobotInfo.fromJson((json['robot'] as Map).cast<String, dynamic>())
            : null,
        robotStatus: json['robot_status'] as String? ?? 'não configurado',
        sessionState: json['session_state'] as String?,
        sessionLivestreamId: json['session_livestream_id'] as String?,
        watchActive: asBool(json['watch_active']),
        watchNickname: json['watch_nickname'] as String?,
        rulesCount: asInt(json['rules_count']),
        messagesCount: asInt(json['messages_count']),
        agencyId: json['agency_id'] == null ? null : asInt(json['agency_id']),
        agencyName: json['agency_name'] as String?,
      );
}

/// One agency with how many of its creators signed up, have a robot connected,
/// have the live watch on, and are being moderated right now.
class AdminAgency {
  final int id;
  final String name;
  final String code;
  final bool active;
  final int usersTotal;
  final int withRobot;
  final int watching;
  final int runningNow;

  const AdminAgency({
    required this.id,
    required this.name,
    this.code = '',
    this.active = true,
    this.usersTotal = 0,
    this.withRobot = 0,
    this.watching = 0,
    this.runningNow = 0,
  });

  factory AdminAgency.fromJson(Map<String, dynamic> json) => AdminAgency(
        id: asInt(json['id']),
        name: json['name'] as String? ?? '',
        code: json['code'] as String? ?? '',
        active: json['active'] == null ? true : asBool(json['active']),
        usersTotal: asInt(json['users_total']),
        withRobot: asInt(json['with_robot']),
        watching: asInt(json['watching']),
        runningNow: asInt(json['running_now']),
      );
}

/// Is the SuperLive egress keeping up? Shown on the Agências tab.
class AdminEgressSlot {
  final int slot;
  final String label;
  final int users;
  final int maxUsers;
  final int activeSessions;
  final int queueDepth;
  final int networkStreak;

  const AdminEgressSlot({
    required this.slot,
    this.label = '',
    this.users = 0,
    this.maxUsers = 0,
    this.activeSessions = 0,
    this.queueDepth = 0,
    this.networkStreak = 0,
  });

  /// Three failures in a row: the proxy behind this IP is not answering.
  bool get networkDown => networkStreak >= 3;
  bool get full => maxUsers > 0 && users >= maxUsers;

  factory AdminEgressSlot.fromJson(Map<String, dynamic> json) => AdminEgressSlot(
        slot: asInt(json['slot']),
        label: json['label']?.toString() ?? '',
        users: asInt(json['users']),
        maxUsers: asInt(json['max_sessions']),
        activeSessions: asInt(json['active_sessions']),
        queueDepth: asInt(json['queue_depth']),
        networkStreak: asInt(json['network_streak']),
      );
}

class AdminCapacity {
  final int egressCount;
  final int seatsTotal;
  final int seatsUsed;
  final List<AdminEgressSlot> slots;
  final int activeSessions;
  final int maxSessions;
  final int suggestedMaxSessions;
  final int deepestQueue;
  final int slowestPollSeconds;

  const AdminCapacity({
    this.seatsTotal = 0,
    this.seatsUsed = 0,
    this.slots = const [],
    this.egressCount = 1,
    this.activeSessions = 0,
    this.maxSessions = 0,
    this.suggestedMaxSessions = 0,
    this.deepestQueue = 0,
    this.slowestPollSeconds = 30,
  });

  factory AdminCapacity.fromJson(Map<String, dynamic> json) {
    final slots = (json['slots'] as List? ?? const []).whereType<Map>().toList();
    int maxOf(String key) =>
        slots.fold<int>(0, (m, s) => asInt(s[key]) > m ? asInt(s[key]) : m);
    final seats = json['seats'] is Map
        ? (json['seats'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return AdminCapacity(
      seatsTotal: asInt(seats['total']),
      seatsUsed: asInt(seats['used']),
      slots: [
        for (final s in slots) AdminEgressSlot.fromJson(s.cast<String, dynamic>())
      ],
      egressCount: asInt(json['egress_count']),
      activeSessions: asInt(json['active_sessions']),
      maxSessions: asInt(json['max_sessions']),
      suggestedMaxSessions: asInt(json['suggested_max_sessions']),
      deepestQueue: maxOf('queue_depth'),
      slowestPollSeconds: maxOf('poll_interval_seconds'),
    );
  }
}

class AdminSessionSummary {
  final int userId;
  final String username;
  final String state;
  final String wsState;
  final String? livestreamId;
  final DateTime? startedAt;
  final String? stopReason;
  final double? watchWaitingSeconds;
  final String? lastError;
  final int messagesSent;
  final int chatSeen;
  final int actionsOk;
  final int actionsFailed;

  const AdminSessionSummary({
    required this.userId,
    required this.username,
    this.state = 'idle',
    this.wsState = 'disconnected',
    this.livestreamId,
    this.startedAt,
    this.stopReason,
    this.watchWaitingSeconds,
    this.lastError,
    this.messagesSent = 0,
    this.chatSeen = 0,
    this.actionsOk = 0,
    this.actionsFailed = 0,
  });

  factory AdminSessionSummary.fromJson(Map<String, dynamic> json) {
    final counters = (json['counters'] as Map?)?.cast<String, dynamic>() ?? {};
    return AdminSessionSummary(
      userId: asInt(json['user_id']),
      username: json['username'] as String? ?? '',
      state: json['state'] as String? ?? 'idle',
      wsState: json['ws_state'] as String? ?? 'disconnected',
      livestreamId: json['livestream_id'] as String?,
      startedAt: parseDate(json['started_at']),
      stopReason: json['stop_reason'] as String?,
      watchWaitingSeconds: (json['watch_waiting_seconds'] as num?)?.toDouble(),
      lastError: json['last_error'] as String?,
      messagesSent: asInt(counters['messages_sent']),
      chatSeen: asInt(counters['chat_seen']),
      actionsOk: asInt(counters['actions_ok']),
      actionsFailed: asInt(counters['actions_failed']),
    );
  }
}
