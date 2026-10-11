import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SubwayApp());
}

class SubwayApp extends StatelessWidget {
  const SubwayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Subway Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E1A),
      ),
      home: const GameScreen(),
    );
  }
}

enum ObstacleKind { low, high, train, coin }

class Obstacle {
  double x;
  final int lane;
  final ObstacleKind kind;
  bool consumed;

  Obstacle({
    required this.x,
    required this.lane,
    required this.kind,
    this.consumed = false,
  });

  double get width {
    switch (kind) {
      case ObstacleKind.train:
        return 100;
      case ObstacleKind.coin:
        return 28;
      case ObstacleKind.low:
      case ObstacleKind.high:
        return 60;
    }
  }

  double get height {
    switch (kind) {
      case ObstacleKind.train:
        return 120;
      case ObstacleKind.coin:
        return 28;
      case ObstacleKind.low:
        return 30;
      case ObstacleKind.high:
        return 85;
    }
  }
}

enum GameStatus { menu, playing, gameOver }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  final Random _rng = Random();

  int _lane = 1;
  double _visualLane = 1;
  double _jumpOffset = 0;
  double _jumpVelocity = 0;
  bool _isJumping = false;
  bool _isSliding = false;
  double _slideTimer = 0;

  final List<Obstacle> _obstacles = [];
  double _speed = 380;
  double _spawnTimer = 0.9;

  double _score = 0;
  int _coinCount = 0;
  int _highScore = 0;

  GameStatus _status = GameStatus.menu;

  double _screenW = 0;
  double _screenH = 0;
  double _laneHeight = 0;
  double _trackTop = 0;

  static const double _playerW = 46;
  static const double _playerH = 92;
  static const double _playerX = 96;
  static const double _gravity = 2600;
  static const double _jumpVelocity0 = -960;
  static const double _slideDuration = 0.6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _loadHighScore();
  }

  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _highScore = prefs.getInt('subway_hs') ?? 0);
  }

  Future<void> _saveHighScore(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('subway_hs', v);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    if (_status != GameStatus.playing) return;
    if (dt <= 0 || dt > 0.1) return;

    _update(dt);
    setState(() {});
  }

  void _update(double dt) {
    _speed = 380 + _score * 0.3;

    _visualLane += (_lane - _visualLane) * (dt * 14).clamp(0.0, 1.0);

    if (_isJumping) {
      _jumpOffset += _jumpVelocity * dt;
      _jumpVelocity += _gravity * dt;
      if (_jumpOffset >= 0) {
        _jumpOffset = 0;
        _jumpVelocity = 0;
        _isJumping = false;
      }
    }

    if (_isSliding) {
      _slideTimer -= dt;
      if (_slideTimer <= 0) {
        _isSliding = false;
      }
    }

    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnTimer = (1.2 - _score * 0.0006).clamp(0.45, 1.2);
      _spawnPattern();
    }

    for (final o in _obstacles) {
      o.x -= _speed * dt;
    }
    _obstacles.removeWhere((o) => o.x + o.width < -30);

    _score += _speed * dt * 0.05;

    _resolveCollisions();
  }

  void _spawnPattern() {
    final lane = _rng.nextInt(3);
    final roll = _rng.nextDouble();

    if (roll < 0.38) {
      final count = 3 + _rng.nextInt(3);
      for (int i = 0; i < count; i++) {
        _obstacles.add(Obstacle(
          x: _screenW + 30 + i * 42,
          lane: lane,
          kind: ObstacleKind.coin,
        ));
      }
    } else if (roll < 0.72) {
      _obstacles.add(Obstacle(
        x: _screenW + 30,
        lane: lane,
        kind: _rng.nextBool() ? ObstacleKind.low : ObstacleKind.high,
      ));
    } else {
      _obstacles.add(Obstacle(
        x: _screenW + 30,
        lane: lane,
        kind: ObstacleKind.train,
      ));
      if (_rng.nextBool()) {
        final safeLane = (lane + 1 + _rng.nextInt(2)) % 3;
        for (int i = 0; i < 4; i++) {
          _obstacles.add(Obstacle(
            x: _screenW + 60 + i * 42,
            lane: safeLane,
            kind: ObstacleKind.coin,
          ));
        }
      }
    }
  }

  void _resolveCollisions() {
    final pRect = _playerRect();
    final playerLeft = _playerX - _playerW / 2;
    final playerRight = _playerX + _playerW / 2;

    for (final o in _obstacles) {
      if (o.consumed) continue;
      if (o.lane != _lane) continue;

      final oRect = _obstacleRect(o);
      final xOverlap = playerRight > oRect.left && playerLeft < oRect.right;
      if (!xOverlap) continue;

      if (o.kind == ObstacleKind.coin) {
        o.consumed = true;
        _coinCount++;
        _score += 10;
        continue;
      }

      if (o.kind == ObstacleKind.train) {
        _endGame();
        return;
      }

      if (pRect.overlaps(oRect)) {
        _endGame();
        return;
      }
    }
  }

  Rect _playerRect() {
    final laneTop = _trackTop + _visualLane * _laneHeight;
    final laneBottom = laneTop + _laneHeight;
    final h = _isSliding ? _playerH * 0.45 : _playerH;
    final top = laneBottom - h + _jumpOffset;
    return Rect.fromLTWH(_playerX - _playerW / 2, top, _playerW, h);
  }

  Rect _obstacleRect(Obstacle o) {
    final laneTop = _trackTop + o.lane * _laneHeight;
    final laneBottom = laneTop + _laneHeight;

    switch (o.kind) {
      case ObstacleKind.low:
        return Rect.fromLTWH(o.x, laneBottom - o.height, o.width, o.height);
      case ObstacleKind.high:
        return Rect.fromLTWH(o.x, laneTop, o.width, o.height);
      case ObstacleKind.train:
        return Rect.fromLTWH(o.x, laneTop + 8, o.width, _laneHeight - 16);
      case ObstacleKind.coin:
        return Rect.fromLTWH(
          o.x,
          laneTop + _laneHeight / 2 - o.height / 2,
          o.width,
          o.height,
        );
    }
  }

  void _startGame() {
    _lane = 1;
    _visualLane = 1;
    _jumpOffset = 0;
    _jumpVelocity = 0;
    _isJumping = false;
    _isSliding = false;
    _slideTimer = 0;
    _obstacles.clear();
    _speed = 380;
    _spawnTimer = 0.9;
    _score = 0;
    _coinCount = 0;
    _status = GameStatus.playing;
    _lastTick = Duration.zero;
    setState(() {});
  }

  void _endGame() {
    _status = GameStatus.gameOver;
    final s = _score.toInt();
    if (s > _highScore) {
      _highScore = s;
      _saveHighScore(s);
    }
    setState(() {});
  }

  void _moveLane(int dir) {
    if (_status != GameStatus.playing) return;
    final next = (_lane + dir).clamp(0, 2);
    if (next != _lane) {
      setState(() => _lane = next);
    }
  }

  void _tryJump() {
    if (_status != GameStatus.playing) return;
    if (_isJumping) return;
    setState(() {
      _isJumping = true;
      _jumpVelocity = _jumpVelocity0;
      _isSliding = false;
    });
  }

  void _trySlide() {
    if (_status != GameStatus.playing) return;
    if (_isJumping) return;
    setState(() {
      _isSliding = true;
      _slideTimer = _slideDuration;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          _screenW = constraints.maxWidth;
          _screenH = constraints.maxHeight;
          _trackTop = _screenH * 0.12;
          _laneHeight = (_screenH * 0.78) / 3;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (d) {
              final v = d.velocity.pixelsPerSecond.dx;
              if (v > 350) {
                _moveLane(1);
              } else if (v < -350) {
                _moveLane(-1);
              }
            },
            onVerticalDragEnd: (d) {
              final v = d.velocity.pixelsPerSecond.dy;
              if (v < -350) {
                _tryJump();
              } else if (v > 350) {
                _trySlide();
              }
            },
            onTap: _status == GameStatus.playing ? null : _startGame,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GamePainter(
                      trackTop: _trackTop,
                      laneHeight: _laneHeight,
                      screenW: _screenW,
                      obstacles: _obstacles,
                      playerRect: _playerRect(),
                      speed: _speed,
                    ),
                  ),
                ),
                if (_status == GameStatus.playing) _buildHud(),
                if (_status == GameStatus.menu) _buildMenu(),
                if (_status == GameStatus.gameOver) _buildGameOver(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHud() {
    return Positioned(
      top: 40,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _pill('النقاط ${_score.toInt()}'),
          _pill('العملات $_coinCount'),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildMenu() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SUBWAY RUN',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: Colors.amber,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'اسحب يمين/يسار لتغيير المسار',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Text(
                'اسحب أعلى للقفز، أسفل للانزلاق',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 42,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'ابدأ اللعب',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'أفضل نتيجة: $_highScore',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameOver() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.65),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'انتهت اللعبة',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'النقاط: ${_score.toInt()}',
                style: const TextStyle(color: Colors.white, fontSize: 22),
              ),
              Text(
                'العملات: $_coinCount',
                style: const TextStyle(color: Colors.amber, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'أفضل نتيجة: $_highScore',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 42,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  final double trackTop;
  final double laneHeight;
  final double screenW;
  final List<Obstacle> obstacles;
  final Rect playerRect;
  final double speed;

  _GamePainter({
    required this.trackTop,
    required this.laneHeight,
    required this.screenW,
    required this.obstacles,
    required this.playerRect,
    required this.speed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintLanes(canvas, size);
    _paintObstacles(canvas);
    _paintPlayer(canvas);
  }

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1B1B3A), Color(0xFF0B0B17)],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  void _paintLanes(Canvas canvas, Size size) {
    final trackRect = Rect.fromLTWH(0, trackTop, screenW, laneHeight * 3);
    canvas.drawRect(trackRect, Paint()..color = const Color(0xFF161625));

    final divider = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2;

    for (int i = 0; i <= 3; i++) {
      final y = trackTop + i * laneHeight;
      canvas.drawLine(Offset(0, y), Offset(screenW, y), divider);
    }

    final sleeper = Paint()
      ..color = const Color(0xFF2A2A44)
      ..strokeWidth = 3;

    final double offset = (speed * 0.6) % 60;
    for (int i = 0; i < 3; i++) {
      final baseY = trackTop + i * laneHeight + laneHeight / 2;
      for (double x = -offset; x < screenW + 60; x += 60) {
        canvas.drawLine(
          Offset(x, baseY - 12),
          Offset(x + 20, baseY + 12),
          sleeper,
        );
      }
    }
  }

  void _paintObstacles(Canvas canvas) {
    for (final o in obstacles) {
      if (o.consumed) continue;
      final rect = _rectFor(o);

      switch (o.kind) {
        case ObstacleKind.train:
          _paintTrain(canvas, rect);
          break;
        case ObstacleKind.low:
        case ObstacleKind.high:
          _paintBarrier(canvas, rect);
          break;
        case ObstacleKind.coin:
          _paintCoin(canvas, rect);
          break;
      }
    }
  }

  Rect _rectFor(Obstacle o) {
    final laneTop = trackTop + o.lane * laneHeight;
    final laneBottom = laneTop + laneHeight;

    switch (o.kind) {
      case ObstacleKind.low:
        return Rect.fromLTWH(o.x, laneBottom - o.height, o.width, o.height);
      case ObstacleKind.high:
        return Rect.fromLTWH(o.x, laneTop, o.width, o.height);
      case ObstacleKind.train:
        return Rect.fromLTWH(o.x, laneTop + 8, o.width, laneHeight - 16);
      case ObstacleKind.coin:
        return Rect.fromLTWH(
          o.x,
          laneTop + laneHeight / 2 - o.height / 2,
          o.width,
          o.height,
        );
    }
  }

  void _paintTrain(Canvas canvas, Rect r) {
    final bodyPaint = Paint()..color = const Color(0xFFB0332E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(8)),
      bodyPaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width, 14),
      Paint()..color = const Color(0xFFD84315),
    );

    final win = Paint()..color = const Color(0xFF1F1F2E);
    final winY = r.top + 28;
    final winH = (r.height - 60).clamp(10.0, r.height);
    for (int i = 0; i < 2; i++) {
      final wx = r.left + 8 + i * (r.width / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(wx, winY, r.width / 2 - 16, winH),
          const Radius.circular(4),
        ),
        win,
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(r.left, r.bottom - 10, r.width, 10),
      Paint()..color = const Color(0xFF2B2B2B),
    );
  }

  void _paintBarrier(Canvas canvas, Rect r) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
    );
    canvas.drawRect(r, Paint()..color = const Color(0xFFFFC107));

    final stripe = Paint()
      ..color = Colors.black
      ..strokeWidth = 8;

    for (double x = r.left - r.height; x < r.right + r.height; x += 18) {
      canvas.drawLine(
        Offset(x, r.top),
        Offset(x + r.height, r.bottom),
        stripe,
      );
    }
    canvas.restore();

    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintCoin(Canvas canvas, Rect r) {
    final center = r.center;
    final radius = r.width / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFFFFC107),
    );
    canvas.drawCircle(
      center,
      radius * 0.7,
      Paint()..color = const Color(0xFFFFE082),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFB8860B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintPlayer(Canvas canvas) {
    final r = playerRect;

    final shadowCenter = Offset(r.center.dx, r.bottom + 4);
    canvas.drawOval(
      Rect.fromCenter(
        center: shadowCenter,
        width: r.width * 0.9,
        height: 10,
      ),
      Paint()..color = Colors.black.withOpacity(0.35),
    );

    final bodyTop = r.top + r.height * 0.28;
    final bodyRect = Rect.fromLTWH(
      r.left + 6,
      bodyTop,
      r.width - 12,
      r.height * 0.52,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFF2E6BFF),
    );

    canvas.drawRect(
      Rect.fromLTWH(
        bodyRect.left + 4,
        bodyRect.top + 4,
        bodyRect.width - 8,
        6,
      ),
      Paint()..color = Colors.white24,
    );

    final legY = bodyRect.bottom;
    final legH = (r.bottom - legY).clamp(0.0, r.height);
    final legW = r.width * 0.22;
    final legPaint = Paint()..color = const Color(0xFF1F1F2E);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + r.width * 0.18, legY, legW, legH),
        const Radius.circular(4),
      ),
      legPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.right - r.width * 0.18 - legW, legY, legW, legH),
        const Radius.circular(4),
      ),
      legPaint,
    );

    final headR = r.width * 0.32;
    final headCenter = Offset(r.center.dx, r.top + headR);
    canvas.drawCircle(
      headCenter,
      headR,
      Paint()..color = const Color(0xFFEFC39B),
    );

    final capPaint = Paint()..color = const Color(0xFFE53935);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(headCenter.dx, headCenter.dy - headR * 0.5),
        width: headR * 2.2,
        height: headR * 1.1,
      ),
      3.14159,
      3.14159,
      true,
      capPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        headCenter.dx - headR * 1.1,
        headCenter.dy - headR * 0.55,
        headR * 2.2,
        headR * 0.35,
      ),
      capPaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(
        headCenter.dx,
        headCenter.dy - headR * 0.3,
        headR * 1.4,
        4,
      ),
      Paint()..color = const Color(0xFFB71C1C),
    );
  }

  @override
  bool shouldRepaint(covariant _GamePainter old) => true;
}