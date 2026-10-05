import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_moderator/core/constants/app_constants.dart';
import 'package:super_moderator/core/models/models.dart';
import 'package:super_moderator/core/services/portal_api_service.dart';
import 'package:super_moderator/core/theme/app_theme.dart';
import 'package:super_moderator/providers/auth_provider.dart';
import 'package:super_moderator/providers/auto_message_provider.dart';
import 'package:super_moderator/providers/bot_provider.dart';
import 'package:super_moderator/screens/auth/login_screen.dart';
import 'package:super_moderator/screens/bot/bot_control_screen.dart';

/// A scripted backend: responses are looked up by "METHOD /path".
class FakeApi extends PortalApiService {
  final Map<String, List<Map<String, dynamic>>> script = {};
  final List<String> calls = [];

  void on(String route, Map<String, dynamic> response) =>
      script.putIfAbsent(route, () => []).add(response);

  Map<String, dynamic> _next(String route) {
    calls.add(route);
    final queue = script[route];
    if (queue == null || queue.isEmpty) {
      return {'statusCode': 0, 'data': null, 'success': false};
    }
    // the last scripted response repeats forever
    return queue.length > 1 ? queue.removeAt(0) : queue.first;
  }

  @override
  Future<Map<String, dynamic>> get(String path,
          {bool requireAuth = true,
          Duration timeout = const Duration(seconds: 15)}) async =>
      _next('GET $path');

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
          {bool requireAuth = true,
          Duration timeout = const Duration(seconds: 15)}) async =>
      _next('POST $path');

  @override
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async =>
      _next('PUT $path');
}

Map<String, dynamic> ok(Object? data) =>
    {'statusCode': 200, 'data': data, 'success': true};
Map<String, dynamic> fail(int status, Object? data) =>
    {'statusCode': status, 'data': data, 'success': false};

Map<String, dynamic> statusPayload({
  bool connected = true,
  bool running = false,
  List<Map<String, dynamic>> chat = const [],
  List<Map<String, dynamic>> actions = const [],
  int totalOk = 0,
  String authMode = 'password',
  Map<String, dynamic>? watch,
}) =>
    {
      'connected': connected,
      'robot': connected
          ? {'id': '777', 'nickname': 'RoboMod', 'avatar': null, 'auth_mode': authMode}
          : null,
      'session': {
        'running': running,
        'state': running ? 'running' : 'idle',
        'ws_state': running ? 'connected' : 'disconnected',
        'livestream_id': running ? 'live1' : null,
        'started_at': '2026-10-03T12:00:00+00:00',
        'stop_reason': null,
        'last_error': null,
        'counters': {
          'messages_sent': 2,
          'chat_seen': chat.length,
          'actions_ok': actions.where((a) => a['ok'] == true).length,
          'actions_failed': 0,
        },
        'recent_chat': chat,
        'recent_actions': actions,
      },
      'totals': {'actions_ok': totalOk, 'actions_failed': 0},
      'watch': watch ??
          {'shared_id': null, 'nickname': null, 'avatar': null, 'active': false},
    };

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('models', () {
    test('PortalUser accepts is_admin as int (what /auth/me used to send)', () {
      final user = PortalUser.fromJson({
        'id': 1,
        'username': 'alice',
        'email': 'a@x.com',
        'is_admin': 0,
        'created_at': '2026-10-03 03:24:06',
      });
      expect(user.isAdmin, isFalse);
      expect(PortalUser.fromJson({'id': 1, 'is_admin': 1, 'created_at': null}).isAdmin, isTrue);
      expect(PortalUser.fromJson({'id': 1, 'is_admin': true}).isAdmin, isTrue);
    });

    test('SQLite timestamps (no zone) are read as UTC', () {
      final parsed = parseDate('2026-10-03 03:24:06')!;
      expect(parsed.isUtc, isTrue);
      expect(parsed.hour, 3);
      expect(parseDate('2026-10-03T03:24:06+00:00')!.hour, 3);
      expect(parseDate(null), isNull);
    });

    test('BotSettings round-trips every field, including kick_permanent', () {
      final s = BotSettings.fromJson({
        'id': 4,
        'user_id': 9,
        'auto_messages_enabled': true,
        'message_interval_seconds': 45,
        'moderation_enabled': false,
        'kick_permanent': true,
        'diamond_immunity_enabled': true,
        'diamond_immunity_threshold': 200,
      });
      expect(s.kickPermanent, isTrue);
      expect(s.moderationEnabled, isFalse);
      expect(s.diamondImmunityEnabled, isTrue);
      expect(s.diamondImmunityThreshold, 200);
      expect(s.toJson()['message_interval_seconds'], 45);
      expect(s.toJson()['kick_permanent'], isTrue);
      expect(s.toJson()['diamond_immunity_threshold'], 200);
      expect(s.toJson().containsKey('end_message_enabled'), isFalse);
    });

    test('BotSettings defaults the diamond immunity threshold to the minimum', () {
      final s = BotSettings(userId: 1);
      expect(s.diamondImmunityEnabled, isFalse);
      expect(s.diamondImmunityThreshold, BotSettings.minDiamondImmunityThreshold);
    });

    test('RobotStatus parses the backend payload', () {
      final status = RobotStatus.fromJson(statusPayload(
        running: true,
        totalOk: 5,
        chat: [
          {'id': 'm1', 'user_id': '2', 'name': 'Bia', 'text': 'passa zap', 'ts': '2026-10-03T12:00:01+00:00', 'action': 'mute'},
        ],
        actions: [
          {'id': 'a1', 'ts': '2026-10-03T12:00:02+00:00', 'action': 'mute', 'target_user_id': '2', 'target_name': 'Bia', 'keyword': 'passa zap', 'message_text': 'passa zap', 'ok': true, 'detail': null},
        ],
      ));
      expect(status.connected, isTrue);
      expect(status.robot!.nickname, 'RoboMod');
      expect(status.session.running, isTrue);
      expect(status.session.recentChat.single.action, 'mute');
      expect(status.session.recentActions.single.targetName, 'Bia');
      expect(status.totalActionsOk, 5);
      expect(RobotStatus.fromJson(statusPayload(connected: false)).connected, isFalse);
    });

    test('RobotStatus carries the favourited streamer', () {
      final status = RobotStatus.fromJson(statusPayload(watch: {
        'shared_id': '555100', 'nickname': 'Streamer', 'avatar': 'http://x/a.png', 'active': true,
      }));
      expect(status.watch.hasTarget, isTrue);
      expect(status.watch.nickname, 'Streamer');
      expect(status.watch.active, isTrue);
      expect(RobotStatus.fromJson(statusPayload()).watch.hasTarget, isFalse);
    });
  });

  group('PortalApiService.errorMessage', () {
    test('uses the server detail when present', () {
      expect(PortalApiService.errorMessage(fail(409, {'detail': 'Essa palavra já está cadastrada'}), 'x'),
          'Essa palavra já está cadastrada');
    });

    test('copes with FastAPI list-style details (used to crash the String cast)', () {
      expect(
          PortalApiService.errorMessage(fail(422, {'detail': [{'msg': 'campo inválido'}]}), 'x'),
          'campo inválido');
    });

    test('hints that the server is down on network failure, else falls back', () {
      expect(PortalApiService.errorMessage({'statusCode': 0, 'data': null}, 'x'),
          contains(AppConstants.localBackendUrl));
      expect(PortalApiService.errorMessage(fail(500, null), 'Falhou'), 'Falhou');
    });
  });

  group('AuthProvider', () {
    Future<void> seedSession() async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyPortalToken: 'tok',
        AppConstants.keyPortalUser: jsonEncode({
          'id': 1, 'username': 'alice', 'email': 'a@x.com', 'is_admin': false,
          'created_at': '2026-10-03T00:00:00.000Z',
        }),
      });
    }

    test('restores the session from /auth/me even though is_admin is 0/1', () async {
      await seedSession();
      final api = FakeApi()
        ..on('GET /auth/me', ok({'id': 1, 'username': 'alice', 'email': 'a@x.com', 'is_admin': 0, 'created_at': '2026-10-03 03:24:06'}));
      final auth = AuthProvider(api: api);
      await auth.initialize();
      expect(auth.isAuthenticated, isTrue);
      expect(auth.user!.username, 'alice');
    });

    test('keeps the saved session when the server is unreachable', () async {
      await seedSession();
      final auth = AuthProvider(api: FakeApi()); // no route -> statusCode 0
      await auth.initialize();
      expect(auth.isAuthenticated, isTrue);
    });

    test('drops the session when the server says 401', () async {
      await seedSession();
      final api = FakeApi()..on('GET /auth/me', fail(401, {'detail': 'Token inválido'}));
      final auth = AuthProvider(api: api);
      await auth.initialize();
      expect(auth.isAuthenticated, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppConstants.keyPortalToken), isNull);
    });

    test('login shows the server message', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeApi()..on('POST /auth/login', fail(401, {'detail': 'Credenciais inválidas'}));
      final auth = AuthProvider(api: api);
      expect(await auth.login('alice', 'x'), isFalse);
      expect(auth.error, 'Credenciais inválidas');
    });
  });

  group('BotProvider', () {
    test('refresh mirrors the backend status', () async {
      final api = FakeApi()
        ..on('GET /robot/status', ok(statusPayload(running: true, totalOk: 3)));
      final bot = BotProvider(api: api, pollInterval: const Duration(hours: 1));
      await bot.refresh();
      expect(bot.isConnected, isTrue);
      expect(bot.isRunning, isTrue);
      expect(bot.botProfile!.nickname, 'RoboMod');
      expect(bot.totalActionsOk, 3);
      bot.dispose();
    });

    test('a failed connect keeps the server message and stays disconnected', () async {
      final api = FakeApi()
        ..on('POST /robot/connect', fail(400, {'detail': 'O SuperLive recusou o login do robô (HTTP 401)'}));
      final bot = BotProvider(api: api);
      expect(await bot.connectRobot('robo@x.com', 'senha'), isFalse);
      expect(bot.error, contains('recusou o login'));
      expect(bot.connectionState, BotConnectionState.error);
      expect(bot.isConnected, isFalse);
      bot.dispose();
    });

    test('connect, start and stop go through the backend', () async {
      final api = FakeApi()
        ..on('POST /robot/connect', ok(statusPayload()))
        ..on('POST /robot/start', ok(statusPayload(running: true)))
        ..on('POST /robot/stop', ok(statusPayload()));
      final bot = BotProvider(api: api, pollInterval: const Duration(hours: 1));
      expect(await bot.connectRobotWithToken('tok'), isTrue);
      expect(bot.isRunning, isFalse);
      expect(await bot.startSession('live1'), isTrue);
      expect(bot.isRunning, isTrue);
      expect(bot.session.livestreamId, 'live1');
      expect(await bot.stopSession(), isTrue);
      expect(bot.isRunning, isFalse);
      expect(api.calls, ['POST /robot/connect', 'POST /robot/start', 'POST /robot/stop']);
      bot.dispose();
    });

    test('start failure surfaces the reason', () async {
      final api = FakeApi()
        ..on('POST /robot/start', fail(400, {'detail': 'O SuperLive recusou o acesso a essa live (HTTP 404)'}));
      final bot = BotProvider(api: api);
      expect(await bot.startSession('nope'), isFalse);
      expect(bot.error, contains('404'));
      bot.dispose();
    });

    test('polls while running and stops polling once the session ends', () async {
      final api = FakeApi()
        ..on('GET /robot/status', ok(statusPayload(running: true)))
        ..on('GET /robot/status', ok(statusPayload(running: true)))
        ..on('GET /robot/status', ok(statusPayload(running: false)));
      final bot = BotProvider(api: api, pollInterval: const Duration(milliseconds: 20));
      await bot.refresh(); // running -> starts the timer
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(bot.isRunning, isFalse);
      final callsAfterEnd = api.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(api.calls.length, callsAfterEnd, reason: 'no polling after the session ended');
      bot.dispose();
    });

    test('polls while a favourited streamer is active, even with no session running',
        () async {
      final api = FakeApi()
        ..on('GET /robot/status', ok(statusPayload(watch: {
          'shared_id': '555100', 'nickname': 'Streamer', 'avatar': null, 'active': true,
        })))
        ..on('GET /robot/status', ok(statusPayload(running: true, watch: {
          'shared_id': '555100', 'nickname': 'Streamer', 'avatar': null, 'active': true,
        })));
      final bot = BotProvider(api: api, pollInterval: const Duration(milliseconds: 20));
      await bot.refresh(); // not running, but watching -> still starts the timer
      expect(bot.isRunning, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bot.isRunning, isTrue, reason: 'picked up the auto-started session via polling');
      bot.dispose();
    });

    test('setWatch saves the favourite and refreshes the status', () async {
      final api = FakeApi()
        ..on('PUT /robot/watch', ok({'shared_id': '555100', 'nickname': 'Streamer', 'avatar': null, 'active': true}))
        ..on('GET /robot/status', ok(statusPayload(watch: {
          'shared_id': '555100', 'nickname': 'Streamer', 'avatar': null, 'active': true,
        })));
      final bot = BotProvider(api: api, pollInterval: const Duration(hours: 1));
      expect(await bot.setWatch('555100', true), isTrue);
      expect(bot.watch.active, isTrue);
      expect(bot.watch.nickname, 'Streamer');
      expect(api.calls, ['PUT /robot/watch', 'GET /robot/status']);
      bot.dispose();
    });

    test('setWatch surfaces the server message on failure', () async {
      final api = FakeApi()
        ..on('PUT /robot/watch', fail(400, {'detail': 'Não encontramos nenhuma conta com esse ID.'}));
      final bot = BotProvider(api: api);
      expect(await bot.setWatch('0', true), isFalse);
      expect(bot.error, 'Não encontramos nenhuma conta com esse ID.');
      bot.dispose();
    });

    test('reset forgets the previous user', () async {
      final api = FakeApi()..on('GET /robot/status', ok(statusPayload(running: true)));
      final bot = BotProvider(api: api, pollInterval: const Duration(hours: 1));
      await bot.refresh();
      bot.reset();
      expect(bot.isConnected, isFalse);
      expect(bot.isRunning, isFalse);
      bot.dispose();
    });

    test('phone login: send code then verify connects the robot', () async {
      final api = FakeApi()
        ..on('POST /robot/connect/phone/send_code', ok({'retry_timeout_seconds': 45}))
        ..on('POST /robot/connect/phone/verify', ok(statusPayload()));
      final bot = BotProvider(api: api);
      final retry = await bot.sendPhoneCode('+5511999999999');
      expect(retry, 45);
      expect(bot.isConnected, isFalse); // code sent, not connected yet
      expect(await bot.connectRobotWithPhoneCode('+5511999999999', '123456'), isTrue);
      expect(bot.isConnected, isTrue);
      bot.dispose();
    });

    test('phone login: server message surfaces on a wrong code', () async {
      final api = FakeApi()
        ..on('POST /robot/connect/phone/verify',
            fail(400, {'detail': 'Código inválido ou expirado'}));
      final bot = BotProvider(api: api);
      expect(await bot.connectRobotWithPhoneCode('+5511999999999', '000000'), isFalse);
      expect(bot.error, 'Código inválido ou expirado');
      expect(bot.connectionState, BotConnectionState.error);
      bot.dispose();
    });

    test('phone login: send-code failure (same anti-bot gate as e-mail) surfaces the reason',
        () async {
      final api = FakeApi()
        ..on('POST /robot/connect/phone/send_code',
            fail(400, {'detail': 'O SuperLive recusou o envio do código por SMS (HTTP 403)'}));
      final bot = BotProvider(api: api);
      expect(await bot.sendPhoneCode('+5511999999999'), isNull);
      expect(bot.error, contains('403'));
      bot.dispose();
    });
  });

  group('screens', () {
    Future<void> pumpLogin(WidgetTester tester, Size size) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider(create: (_) => AuthProvider(api: FakeApi()))],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const LoginScreen()),
        ),
      );
      await tester.pump(const Duration(seconds: 1)); // finish the entrance animation
    }

    testWidgets('login screen renders on a narrow window (it threw an unbounded-width error)',
        (tester) async {
      // Narrow layout (<= 800px). 480px rather than 375px because flutter_test draws text
      // with the square "Ahem" font, which makes the footer row overflow below ~480px.
      await pumpLogin(tester, const Size(480, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('Bem-vindo de volta!'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
    });

    testWidgets('login screen renders on a wide desktop window', (tester) async {
      await pumpLogin(tester, const Size(1280, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('Bem-vindo de volta!'), findsOneWidget);
      expect(find.text('Moderação automática'), findsOneWidget); // hero panel
    });

    testWidgets('robot screen shows the real chat, actions and counters (no literal \${...})',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 2400);
      addTearDown(tester.view.resetPhysicalSize);

      final api = FakeApi()
        ..on(
          'GET /robot/status',
          ok(statusPayload(
            running: true,
            totalOk: 7,
            chat: [
              {'id': 'm1', 'user_id': '1', 'name': 'Ana', 'text': 'oi gente', 'ts': '2026-10-03T12:00:01+00:00', 'action': null},
              {'id': 'm2', 'user_id': '2', 'name': 'Bia', 'text': 'me passa zap', 'ts': '2026-10-03T12:00:02+00:00', 'action': 'mute'},
            ],
            actions: [
              {'id': 'a1', 'ts': '2026-10-03T12:00:03+00:00', 'action': 'mute', 'target_user_id': '2', 'target_name': 'Bia', 'keyword': 'passa zap', 'message_text': 'me passa zap', 'ok': true, 'detail': null},
              {'id': 'a2', 'ts': '2026-10-03T12:00:04+00:00', 'action': 'kick', 'target_user_id': '3', 'target_name': 'Caio', 'keyword': 'feia', 'message_text': 'feia', 'ok': false, 'detail': 'not a moderator'},
            ],
          )),
        );
      final bot = BotProvider(api: api, pollInterval: const Duration(hours: 1));
      addTearDown(bot.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api: api)),
            ChangeNotifierProvider<BotProvider>.value(value: bot),
            ChangeNotifierProvider<AutoMessageProvider>(create: (_) => AutoMessageProvider(api: api)),
          ],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: BotControlScreen())),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(find.text('RoboMod'), findsOneWidget);
      expect(find.text('Moderando a live...'), findsOneWidget);
      expect(find.text('Chat conectado'), findsOneWidget);
      expect(find.textContaining('oi gente', findRichText: true), findsOneWidget);
      expect(find.text('silenciado'), findsOneWidget);
      expect(find.text('Silenciou Bia'), findsOneWidget);
      expect(find.text('Falhou ao banir Caio'), findsOneWidget);
      expect(find.text('not a moderator'), findsOneWidget);
      expect(find.text('7 no total'), findsOneWidget);
      // the old build printed these placeholders verbatim
      expect(find.textContaining(r'${', findRichText: true), findsNothing);
      bot.reset(); // cancels the polling timer so the test can finish cleanly
    });

    testWidgets('robot screen offers e-mail/password and token login when disconnected',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 1600);
      addTearDown(tester.view.resetPhysicalSize);

      final api = FakeApi()..on('GET /robot/status', ok(statusPayload(connected: false)));
      final bot = BotProvider(api: api);
      addTearDown(bot.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api: api)),
            ChangeNotifierProvider<BotProvider>.value(value: bot),
            ChangeNotifierProvider<AutoMessageProvider>(create: (_) => AutoMessageProvider(api: api)),
          ],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: BotControlScreen())),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Conectar Robô'), findsOneWidget);
      expect(find.text('E-mail e senha'), findsOneWidget);
      expect(find.text('Colar token'), findsOneWidget);
      await tester.tap(find.text('Colar token'));
      await tester.pump();
      expect(find.text('Token da sessão do robô'), findsOneWidget);
      expect(find.text('Iniciar moderação'), findsNothing); // only after connecting
    });

    testWidgets('robot screen: phone login sends a code then verifies it',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 1600);
      addTearDown(tester.view.resetPhysicalSize);

      final api = FakeApi()
        ..on('GET /robot/status', ok(statusPayload(connected: false)))
        ..on('POST /robot/connect/phone/send_code', ok({'retry_timeout_seconds': 30}))
        ..on('POST /robot/connect/phone/verify', ok(statusPayload(authMode: 'phone')));
      final bot = BotProvider(api: api, pollInterval: const Duration(hours: 1));
      addTearDown(bot.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api: api)),
            ChangeNotifierProvider<BotProvider>.value(value: bot),
            ChangeNotifierProvider<AutoMessageProvider>(create: (_) => AutoMessageProvider(api: api)),
          ],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: BotControlScreen())),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Celular'));
      await tester.pump();
      expect(find.text('Enviar código por SMS'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Telefone (com código do país)'), '+5511999999999');
      await tester.tap(find.text('Enviar código por SMS'));
      await tester.pump(); // starts the request
      await tester.pump(); // applies the result

      expect(find.text('Código recebido por SMS'), findsOneWidget);
      expect(find.text('Confirmar código'), findsOneWidget);
      expect(find.textContaining('Reenviar código'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Código recebido por SMS'), '123456');
      await tester.tap(find.text('Confirmar código'));
      await tester.pump();
      await tester.pump();

      expect(find.text('RoboMod'), findsOneWidget);
      expect(find.text('Conectado com celular'), findsOneWidget);
      expect(find.text('Desconectar'), findsOneWidget);
    });

    testWidgets('robot screen: finding a streamer by her public id fills the livestream id',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 2400);
      addTearDown(tester.view.resetPhysicalSize);

      final api = FakeApi()
        ..on('GET /robot/status', ok(statusPayload(running: false)))
        ..on(
          'POST /robot/lookup_streamer',
          ok({'nickname': 'Fulana', 'avatar': null, 'live': true, 'livestream_id': 'live42'}),
        );
      final bot = BotProvider(api: api, pollInterval: const Duration(hours: 1));
      addTearDown(bot.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api: api)),
            ChangeNotifierProvider<BotProvider>.value(value: bot),
            ChangeNotifierProvider<AutoMessageProvider>(create: (_) => AutoMessageProvider(api: api)),
          ],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: BotControlScreen())),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextField, 'ID público da streamer'), '69622983');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      await tester.pump();

      expect(find.text('Fulana'), findsOneWidget);
      expect(find.text('ao vivo agora'), findsOneWidget);
      final liveIdField =
          tester.widget<TextField>(find.widgetWithText(TextField, 'ID da Live (livestream_id)'));
      expect(liveIdField.controller!.text, 'live42');
    });

    testWidgets('robot screen: an offline streamer is reported without an error banner',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 2400);
      addTearDown(tester.view.resetPhysicalSize);

      final api = FakeApi()
        ..on('GET /robot/status', ok(statusPayload(running: false)))
        ..on(
          'POST /robot/lookup_streamer',
          ok({'nickname': 'Fulana', 'avatar': null, 'live': false, 'livestream_id': null}),
        );
      final bot = BotProvider(api: api, pollInterval: const Duration(hours: 1));
      addTearDown(bot.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api: api)),
            ChangeNotifierProvider<BotProvider>.value(value: bot),
            ChangeNotifierProvider<AutoMessageProvider>(create: (_) => AutoMessageProvider(api: api)),
          ],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: BotControlScreen())),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextField, 'ID público da streamer'), '1');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      await tester.pump();

      expect(find.text('não está ao vivo'), findsOneWidget);
      final liveIdField =
          tester.widget<TextField>(find.widgetWithText(TextField, 'ID da Live (livestream_id)'));
      expect(liveIdField.controller!.text, isEmpty); // not filled when she's offline
    });
  });
}
