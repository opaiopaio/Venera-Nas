import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';

import 'smb_config.dart';
import 'smb_serial.dart';

/// High-level client for interacting with an SMB share.
///
/// Wraps [Smb2Pool] from the `dart_smb2` package, providing convenience
/// methods for listing directories and reading files that fit naturally
/// into Venera's local-comic pipeline.
///
/// ⭐ 2026-10-24：**所有原生调用都经过 [SmbSerial]** ✓ —— libsmb2 在并发使用 /
/// 读到一半被 disconnect 时会原生崩溃（`0xc0000005` ✓，事件日志实证 ✓）。
/// 闸门放在这一层 ✓ ⇒ 阅读器、封面、切章列目录、下载器、导入器**共用同一把锁** ✓。
///
/// Usage:
/// ```dart
/// final client = SmbClient(config: myConfig);
/// await client.connect();
/// final entries = await client.listDirectory('Comics/Series');
/// final bytes = await client.readFile('Comics/Series/Chapter1/001.jpg');
/// await client.disconnect();
/// ```
class SmbClient {
  final SmbConfig config;

  Smb2Pool? _pool;

  /// ⭐ 2026-10-25：连接被判定为**不可再用** ✓（超时 / 连接类错误后置位 ✓）——
  /// 此时直接新建连接 ✓（旧连接引用已丢弃 ✓，不 disconnect ✓，见 [_guard] ✓）。
  bool _dead = false;

  /// ⭐ 2026-10-25：上次"连接失败"的时间 ✓ —— 用于**失败冷却** ✓（见 [connect] ✓）。
  DateTime? _lastConnectFailureAt;

  /// ⭐ 2026-10-25：**连接单飞** ✓ —— 并发首连只允许一个 `Smb2Pool.connect` ✓。
  ///
  /// 成因：阅读器并发 2 时两条路径会同时走到 "`_pool == null` ⇒ 建池" ✗；
  /// 先完成的池被后完成的覆盖 ⇒ 另一条连接池泄漏 ✓（每条 4 个 isolate ✓），
  /// NAT/路由器侧也会多占一批 SMB 会话 ✓。现在所有调用者共享同一个 Future ✓。
  Future<void>? _connecting;

  static const _connectCooldown = Duration(seconds: 3);

  /// ⭐ 2026-10-25：**连接单独用 40s 预算** ✓ ——
  /// 原先生效的是 [_opTimeout]（25s）✗，比底层 `Smb2Pool.connect(timeoutSeconds: 30)`
  /// 还短 ⇒ 原生连接仍在跑时 Dart 层先超时、丢引用 ✗（每次超时泄漏一池 ✓）。
  /// 现在给 connect 留出比原生 30s 更宽的 40s ✓，让它自己先返回失败 ✓。
  static const _connectTimeout = Duration(seconds: 40);

  /// ⭐ 2026-10-25：断开前等待在途原生操作的**上限** ✓（3~5s ✓）。
  /// 底层 `Smb2Pool.disconnect()` 会给每个 worker 5s 后直接 `Isolate.kill` ✗；
  /// 若同步 FFI 读还在跑就会被强杀 ⇒ `0xc0000005` ✓。先 drain 可以覆盖绝大多数读 ✓。
  static const _disconnectDrainTimeout = Duration(seconds: 4);

  /// ⭐ 2026-10-25：下载是长操作 ✓（大文件可能几分钟 ✓），不能套 25s 的普通操作预算 ✗。
  static const _downloadTimeout = Duration(minutes: 10);

  /// ⭐ 2026-10-25：**单客户端内并发上限** ✓（连接池 4 个 worker ✓，留 1 个余量 ✓）。
  /// 只限制"同一客户端"✓ —— 阅读器与封面各用不同客户端 ✓ ⇒ 互不阻塞 ✓（流式阅读的关键 ✓）。
  static const _maxConcurrentOps = 3;
  final _ops = _OpLimiter(_maxConcurrentOps);

  SmbClient({required this.config});

  /// ⭐ 2026-10-25：**共享客户端池** ✓ —— 供"短操作"复用连接 ✓。
  ///
  /// 为什么需要（实测日志 ✓）：历史页封面是 `ImageProvider` ✓，**每个封面**都 `new SmbClient()` ✗
  /// ⇒ 每次 `Smb2Pool.connect(workers: 4)` = **4 条连接** ✗；25 个封面 + 图片层失败重试
  /// ⇒ **连接被刷爆** ✗ ⇒ 路由器 SMB 侧资源/带宽占满 ✓ ⇒ 扫描/读图全部排队超时 ✗
  ///（日志现象：`Socket connect failed with 10060` ✓）
  ///
  /// 现在：按 主机+共享 缓存一个客户端 ✓ ⇒ 封面 / 历史 / 导入 / 切章列表**共用**连接 ✓，
  /// 只保留一条会话 ✓（阅读器另有自己的复用逻辑 ✓）。
  ///
  /// ⭐ 2026-10-25：池**有进有出** ✓ —— 60s 空闲回收 ✓ + 数量上限 8 ✓（见 [_sweepIdleShared]
  /// / [_enforceSharedLimit] ✓），避免长时间运行后把 NAS 会话占满 ✓。
  static final Map<String, SmbClient> _sharedClients = {};

  /// ⭐ 2026-10-25：**统一会话键** ✓ —— 客户端池与阅读器（`ReaderImageProvider`）共用这一份 ✓。
  ///
  /// 与 [SmbConfig.cacheKey]（资源键 `host|port|share` ✓）的区别 ✓：会话键额外带上
  /// **凭据 + 协议选项** ✓ —— 换账号、改签名/加密/方言都必须**新建连接** ✗，
  /// 否则会把上一个账号协商好的会话错误复用 ✓。
  /// 密码只取 hashCode ✓（键可能被调试输出 / 日志打印 ✓，不落明文 ✓）。
  static String cacheKey(SmbConfig config) =>
      '${config.cacheKey}|${config.username}|${config.password.hashCode}|'
      '${config.domain}|${config.signing}|${config.seal}|${config.version.name}';

  /// 共享客户端的**最后使用时间** ✓（成功操作 / 重新取用都会刷新 ✓）。
  ///
  /// ⭐ 2026-10-25：用于**空闲回收** ✓ —— 旧实现只增不减 ✗ ⇒ 给每个 `host+share`
  /// 都留一条长期空闲会话 ✓，NAS / 路由器侧会话与句柄会被慢慢吃光 ✗。
  DateTime? _lastSharedUse;

  /// 空闲回收阈值 ✓：60s 无操作即断开 ✓（再用时 [shared] 会按需重建 ✓）。
  static const _sharedIdleTimeout = Duration(seconds: 60);

  /// 共享客户端数量上限 ✓：每条连接池内部已有 worker ✓，8 条已足够覆盖
  /// 阅读器 + 封面 + 历史 + 导入 ✓（再多只会把 NAS 连接数打满 ✓）。
  static const _maxSharedClients = 8;

  /// 空闲巡检周期 ✓（比回收阈值短 ⇒ 最迟约 80s 内断开 ✓）。
  static const _idleSweepInterval = Duration(seconds: 20);

  /// 空闲巡检定时器 ✓（只在池非空时存在 ✓，池空即取消 ✓）。
  static Timer? _idleReaper;

  /// 取得（必要时创建）**共享**客户端 ✓ —— ⚠️ 调用方**不要** `disconnect()` ✗
  ///（共享连接被断开会影响其它调用方 ✓；需要断开时用 [closeAllShared] ✓）。
  ///
  /// ⭐ 2026-10-25：取用前**先回收空闲连接并守住数量上限** ✓（见 [_sweepIdleShared] /
  /// [_enforceSharedLimit] ✓）—— 共享池不能"只进不出"✗。
  static SmbClient shared(SmbConfig config) {
    final key = cacheKey(config);
    _sweepIdleShared(exceptKey: key);
    final client = _sharedClients.putIfAbsent(
      key,
      () => SmbClient(config: config),
    );
    client._lastSharedUse = DateTime.now();
    _ensureIdleReaper();
    _enforceSharedLimit(exceptKey: key);
    return client;
  }

  /// 当前共享客户端数量 ✓（自检 / 排查连接数异常时用 ✓）。
  static int get sharedClientCount => _sharedClients.length;

  /// 断开并清空所有共享客户端 ✓（阅读器"重置 SMB 连接" / 退出时用 ✓）。
  ///
  /// ⭐ 2026-10-25：**并行 drain 再断** ✓ —— 每个 [disconnect] 内部都会先等在途
  /// 原生操作（最多 [_disconnectDrainTimeout] ✓）；这里并行等待，避免 N 个客户端
  /// 串行各等 4s ⇒ 重置按钮最多卡十几秒 ✗。
  ///
  /// ⭐ 2026-10-25：**重置必须真正清空** ✓ —— 除了断开连接，还要
  /// ① 取消空闲巡检定时器 ✓（否则池空后还挂着一个周期任务 ✗）；
  /// ② 清掉 [_sharedClients]（先清再断 ✓，断的过程中新请求不会拿到待断连接 ✓）。
  static Future<void> closeAllShared() async {
    _idleReaper?.cancel();
    _idleReaper = null;
    final list = _sharedClients.values.toList();
    _sharedClients.clear();
    await Future.wait(
      list.map((client) async {
        try {
          await client.disconnect();
        } catch (_) {
          // 单条失败不影响其它 ✓。
        }
      }),
    );
  }

  /// 回收**空闲**共享连接 ✓：超过 [_sharedIdleTimeout] 无操作 ⇒ 移除并异步断开 ✓。
  ///
  /// ⚠️ **只回收不忙的** ✓ —— 正在读 / 正在建连 / 有排队等待者的连接绝不能断 ✗
  ///（libsmb2 读到一半被 disconnect 会 `0xc0000005` 崩溃 ✓，已有事件日志实证 ✓）。
  /// [exceptKey] = 本次要取用的键 ✓（刚被取用的那条不走回收 ✓）。
  static void _sweepIdleShared({String? exceptKey}) {
    if (_sharedClients.isEmpty) return;
    final now = DateTime.now();
    final stale = <String>[];
    _sharedClients.forEach((key, client) {
      if (key == exceptKey) return;
      final last = client._lastSharedUse;
      if (last == null) return;
      if (now.difference(last) < _sharedIdleTimeout) return;
      if (client._isBusy) return;
      stale.add(key);
    });
    for (final key in stale) {
      final client = _sharedClients.remove(key);
      if (client != null) unawaited(client._closeQuietly());
    }
  }

  /// 守住共享池数量上限 ✓：超限时淘汰**最久未用**且**不忙**的客户端 ✓。
  ///
  /// ⚠️ 若所有客户端都在忙 ⇒ **暂不淘汰** ✓（宁可短时超限，也不硬断在途连接 ✗）。
  static void _enforceSharedLimit({String? exceptKey}) {
    while (_sharedClients.length > _maxSharedClients) {
      String? oldestKey;
      DateTime? oldestAt;
      _sharedClients.forEach((key, client) {
        if (key == exceptKey) return;
        if (client._isBusy) return;
        final at = client._lastSharedUse;
        if (at == null) return;
        if (oldestAt == null || at.isBefore(oldestAt!)) {
          oldestAt = at;
          oldestKey = key;
        }
      });
      if (oldestKey == null) return;
      final client = _sharedClients.remove(oldestKey);
      if (client != null) unawaited(client._closeQuietly());
    }
  }

  /// 起一个空闲巡检定时器 ✓（池空了就自己取消 ✓，避免空转 ✗）。
  static void _ensureIdleReaper() {
    if (_idleReaper != null) return;
    _idleReaper = Timer.periodic(_idleSweepInterval, (_) {
      _sweepIdleShared();
      if (_sharedClients.isEmpty) {
        _idleReaper?.cancel();
        _idleReaper = null;
      }
    });
  }

  /// 是否还有在途 / 排队的操作 ✓（连接池不是"空闲"就返回 true ✓）。
  bool get _isBusy => _connecting != null || _ops.isBusy;

  /// 静默断开 ✓（回收路径用：失败只意味着"下次重建"✓，不必上报 ✓）。
  Future<void> _closeQuietly() async {
    try {
      await disconnect();
    } catch (_) {
      // 忽略：客户端已从池里摘除 ✓，下次 shared() 会新建 ✓。
    }
  }

  /// Whether the client is currently connected.
  ///
  /// ⚠️ 只表示"池对象非空" ✓（复查记录 ✓）—— 连接可能已被服务器断开 ✓；
  /// 真正的失败会在下一次原生调用上暴露 ✓。
  bool get isConnected => _pool != null && !_dead;

  /// Connect to the SMB share.
  ///
  /// [high] = true 表示"用户在等" ✓（阅读器当前页 ✓）；后台任务用 false ✓。
  Future<void> connect({bool high = false}) {
    // ⭐ 2026-10-25：**单飞** ✓ —— 并发首连共享同一个 Future ✓（见 [_connecting] ✓）。
    final pending = _connecting;
    if (pending != null) {
      return pending;
    }
    final future = _connect(high: high);
    _connecting = future;
    // 无论成功/失败都只清自己 ✓（防止旧 Future 的收尾把新连接标记清掉 ✗）。
    future.whenComplete(() {
      if (identical(_connecting, future)) {
        _connecting = null;
      }
    }).ignore();
    return future;
  }

  Future<void> _connect({required bool high}) async {
    // ⚠️ 2026-10-24：底层库（`dart_smb2` → libsmb2）**没有端口参数** ✗ ⇒ 非 445 端口
    // 原来会**静默连到 445** ✗（用户只看到"连不上"、查不出原因 ✓）⇒ 这里改为**明确报错** ✓。
    if (config.port != 445) {
      throw "SMB 端口 ${config.port} 暂不支持：当前底层库仅支持 445 端口，"
          "请在 NAS/路由器上使用标准 SMB 端口（445）。";
    }
    // ⭐ 2026-10-25：**连接失败冷却** ✓ —— 实测日志里 `Smb2Pool.connect` 本身会**卡住不返回** ✗
    //（服务器侧会话耗尽 / 网络半断 ✓）⇒ 若不加限制，封面等并发任务会**不停重连** ✗，
    // 每个都要等很久 ⇒ 界面全卡 ✓。冷却期内**直接快速失败** ✓，让界面给出"稍后重试"✓。
    final lastFailure = _lastConnectFailureAt;
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < _connectCooldown) {
      throw "SMB 连接失败（刚失败过，请稍后重试；或点「设置 → 网络 → SMB 服务器 → 重置 SMB 连接」）。";
    }
    if (_pool != null) {
      // 已连着也算一次成功 ✓：清掉冷却与 dead 标记 ✓，避免复用连接却继续快速失败 ✗。
      _lastConnectFailureAt = null;
      _dead = false;
      return;
    }
    try {
      await _guard(
        () async {
          // ⭐ 已连接就直接复用 ✓（共享客户端会被频繁 `connect()` ✓）。
          if (_pool != null) return;
          // ⭐⭐ 2026-10-25（实测日志 ✓）：**建连必须全局串行** ✗ ——
          // `Failed to parse fixed part of command payload` 是 libsmb2 在**多 isolate 同时
          // `smb2_init_context`** 时的典型症状 ✓（其全局 `active_contexts` 列表无锁 ✗）。
          // 数据读可以并发 ✓（每池独立 worker ✓），但**建连/断连**必须排队 ✓ ——
          // 用 `SmbSerial.run` 作"上下文生命周期锁" ✓，这也是 v1 审计第 2 条的修法 ✓。
          _pool = await SmbSerial.run(
            () => Smb2Pool.connect(
              host: config.host,
              share: config.share,
              user: config.username,
              password: config.password,
              domain: config.domain,
              // 原生 30s 先返回 ✓，Dart 层 [_connectTimeout] 40s 兜底 ✓ ——
              // 原先 Dart 层只有 25s，反而比原生 30s 先超时 ✗（连接还在跑就丢引用 ✓）。
              timeoutSeconds: 30,
              // ⭐ 2026-10-25（实测 ✓）：**单 worker** ✓ —— 有些服务器（路由器内置 SMB 服务 ✓）
              // 对**同一会话的多个 worker 并发握手**处理不稳 ✗ ⇒ 报
              // Failed to parse fixed part of command payload ✗；先降为 1 ✓
              //（libsmb2 池内部仍会排队 ✓，数据读的并发由我们自己的 limiter 控制 ✓）。
              workers: 1,
              // ⭐ 2026-10-24：协议选项透传 ✓（服务器"强制签名/加密"或需指定方言时用得上 ✓）。
              signing: config.signing,
              seal: config.seal,
              version: config.version,
            ),
            high: high,
          );
          _dead = false;
        },
        high: high,
        timeout: _connectTimeout,
      );
      _lastConnectFailureAt = null;
      _dead = false;
    } catch (e) {
      // ⭐⭐ 2026-10-25（用户实测追问 ✓）：**「自动」要真的会动态降级** ✓
      //
      // 说明 ✓：`version: any` 只是"客户端在协商里**列出**所有方言" ✓，
      // **由服务器挑最高公共版本** ✓ —— 若某台服务器的最高版本（如 3.1.1 / 3.0 ✓）
      // 自身有问题 ✗，协商就会**一直选中那个坏版本** ⇒ 表现为"自动也连不上" ✗
      //（用户截图 ✓：只有显式 `SMB 3.0.2` + 关签名能连 ✓）。
      //
      // 所以这里补上**自动降级链** ✓：按"关签名/关加密 → 3.0.2 → 2.1"逐级试 ✓，
      // 任何一套成功就采用 ✓（用户不需要手动一项项改 ✓）。
      final candidates = <SmbConfig>[];
      void addCandidate(SmbConfig c) {
        // 去重 ✓（同样的参数不要重复试 ✓）。
        for (final existing in candidates) {
          if (existing.host == c.host &&
              existing.share == c.share &&
              existing.username == c.username &&
              existing.password == c.password &&
              existing.domain == c.domain &&
              existing.signing == c.signing &&
              existing.seal == c.seal &&
              existing.version == c.version) {
            return;
          }
        }
        candidates.add(c);
      }

      // ① 只关签名/加密（保留用户指定版本或自动 ✓）
      if (config.signing || config.seal) {
        addCandidate(config.copyWith(signing: false, seal: false));
      }
      // ② 全关 + 自动
      addCandidate(
        config.copyWith(signing: false, seal: false, version: Smb2Version.any),
      );
      // ③ 全关 + 3.0.2（老 Samba / ksmbd 常见可用 ✓）
      addCandidate(
        config.copyWith(signing: false, seal: false, version: Smb2Version.v302),
      );
      // ④ 全关 + 2.1（最保守 ✓）
      addCandidate(
        config.copyWith(signing: false, seal: false, version: Smb2Version.v210),
      );

      for (final candidate in candidates) {
        try {
          final fallback = SmbClient(config: candidate);
          await fallback.connect(high: high);
          // 所有权转移 ✓：把池交给本实例，避免 fallback 被回收时误断 ✓。
          _pool = fallback._pool;
          fallback._pool = null;
          _lastConnectFailureAt = null;
          _dead = false;
          return;
        } catch (_) {
          // 这一套不行 ⇒ 试下一套 ✓。
        }
      }
      // ⚠️ 冷却窗口 3s ✓：不长时间藏住真实错误 ✓。
      _lastConnectFailureAt = DateTime.now();
      rethrow;
    }
  }

  /// Disconnect from the SMB share and release resources.
  ///
  /// ⭐ 2026-10-25（P0 ✓）：**先等在途原生操作跑完，再 disconnect** ✓ ——
  /// `dart_smb2` 的 worker 在 `close` 5s 后直接 `Isolate.kill` ✓；而读文件是同步 FFI ✓，
  /// 读到一半被 kill 就是 `0xc0000005` ✓。所以先 [_ops.drain]（最多 4s ✓）再断 ✓。
  Future<void> disconnect() async {
    final pool = _pool;
    if (pool == null) return;
    // 先摘引用 ✓：排队中的操作醒来会因 `_p` 为空快速失败 ✓，不会在断开后又发原生调用 ✗。
    _pool = null;
    await _ops.drain(timeout: _disconnectDrainTimeout);
    await SmbSerial.run(() async {
      await pool.disconnect();
    });
  }

  Smb2Pool get _p {
    final pool = _pool;
    if (pool == null) {
      throw StateError('SmbClient is not connected. Call connect() first.');
    }
    return pool;
  }

  /// ⭐ 2026-10-25：**单个原生操作的超时** ✓
  ///
  /// 为什么必须加（实测日志 ✓）：服务器偶发不响应（ksmbd 上出现过 ✓）⇒ 原生读
  /// **永远不返回** ✗ ⇒ 全局闸门被占死 ✗ ⇒ 后面列目录 / 读图全部排队 ⇒
  /// "扫描转圈 / 打开漫画无限转圈"、取消也很慢 ✓（日志里同一页每 7~10 秒重试一次 ✓）。
  static const _opTimeout = Duration(seconds: 25);

  /// 带超时 + 出错自动"弃用连接"的原生操作包装 ✓。
  ///
  /// ⚠️ 超时/连接类错误后**故意不 disconnect** ✗ —— 原生调用可能仍在跑 ✓，
  /// 此时断开会造成 `0xc0000005` 访问冲突 ✓（事件日志实证 ✓）。
  /// 做法是**丢弃引用** ✓：旧连接自生自灭（泄漏一条 ✓），后续操作**新建连接** ✓
  /// ⇒ 用户看到"超时，请重试"✓，而不是永远转圈 ✗。
  /// ⭐ 2026-10-25：**只在 connection / timeout 时作废连接** ✓ ——
  /// `unknown` 可能只是文件/权限/协议层的普通错误 ✓，把它也当断线会无谓丢池 ✗。
  ///
  /// ⭐ 2026-10-25（第二轮，用户反馈 ✓）：**数据操作改为"单客户端内并发 ≤3"** ✓ ——
  /// 之前走**全局串行闸门** ✗ ⇒ 所有读图/封面/扫描排成一条队 ✗ ⇒ 表现为
  /// "像顺序加载、最后一页要等前面全部加载完" ✗，完全不是**云端流式阅读**想要的体验 ✓。
  /// `dart_smb2` 的连接池本身有 4 个 worker ✓（就是为并发准备的 ✓），
  /// 只要**不在读的过程中断开连接** ✓ 就是安全的 ✓（崩溃真因是断开 ✓，已规避 ✓）。
  /// 全局闸门现在只保留给 **connect / disconnect** 这类状态切换 ✓。
  Future<T> _guard<T>(
    Future<T> Function() op, {
    bool high = false,
    Duration timeout = _opTimeout,
  }) async {
    // ⭐ high 现在**真的生效** ✓：由 [_OpLimiter] 分成 high / low 两条等待队列 ✓，
    // 前台读图不会排在一堆封面/预取后面 ✗。
    await _ops.acquire(high: high);
    try {
      final operation = op();
      // ⭐ 记录"原生 Future 尚未结束" ✓ —— 即使 Dart 层 timeout 先返回，
      // disconnect 也要等它真正结束再断 ✓（`timeout` 不会取消原生读 ✓）。
      _ops.nativeStarted();
      operation.whenComplete(_ops.nativeFinished).ignore();
      return await operation.timeout(timeout);
    } on TimeoutException {
      _invalidate();
      throw "SMB 操作超时（服务器无响应）。可在「设置 → 网络 → SMB 服务器」"
          "点「重置 SMB 连接」后重试。";
    } on Smb2Exception catch (e) {
      if (e.type == Smb2ErrorType.connection ||
          e.type == Smb2ErrorType.timeout) {
        _invalidate();
      }
      rethrow;
    } finally {
      // 信号量名额在 Dart 层结束时归还 ✓；[nativeStarted]/[nativeFinished] 单独统计
      // "原生是否真的跑完" ✓，供 disconnect 的 drain 使用 ✓。
      _ops.release();
      // ⭐ 2026-10-25：每次原生操作结束都刷新"最后使用时间" ✓ ——
      // 空闲回收据此判断"60s 无操作" ✓（否则只按 `shared()` 取用时间算 ✗，
      // 一次长时间连续阅读会被误判为空闲而断开 ✓）。
      _lastSharedUse = DateTime.now();
    }
  }

  /// 丢弃当前连接引用（**不 disconnect** ✓，见 [_guard] 注释 ✓）。
  void _invalidate() {
    _pool = null;
    _dead = true;
  }

  /// List the contents of a directory on the SMB share.
  ///
  /// [path] is relative to the share root (e.g. `'Comics'` or `''`).
  /// Returns a list of [SmbEntry] objects with name, path, type and size.
  Future<List<SmbEntry>> listDirectory(String path, {bool high = false}) async {
    final entries = await _guard(() => _p.listDirectory(path), high: high);
    return entries.map((e) {
      final entryPath = path.isEmpty ? e.name : '$path/${e.name}';
      return SmbEntry(
        name: e.name,
        path: entryPath,
        isDirectory: e.isDirectory,
        size: e.size,
        modified: e.stat.modified,
      );
    }).toList();
  }

  /// Check whether a path exists on the SMB share.
  Future<bool> exists(String path) async {
    try {
      await stat(path);
      return true;
    } on Smb2Exception catch (e) {
      if (e.type == Smb2ErrorType.fileNotFound) {
        return false;
      }
      rethrow;
    }
  }

  /// Read the entire contents of a file on the SMB share into memory.
  ///
  /// ⭐ [high] = true 表示"用户在等"（阅读器当前页 ✓）—— 会优先于后台预取 ✓。
  Future<Uint8List> readFile(String path, {bool high = false}) async {
    return _guard(() => _p.readFile(path), high: high);
  }

  /// Read a byte range from a file on the SMB share.
  ///
  /// [offset] is 0-based. [length] is the maximum number of bytes to read.
  Future<Uint8List> readFileRange(
    String path, {
    int offset = 0,
    required int length,
    bool high = false,
  }) async {
    return _guard(
      () => _p.readFileRange(path, offset: offset, length: length),
      high: high,
    );
  }

  /// Get file metadata without reading its contents.
  Future<Smb2Stat> stat(String path, {bool high = false}) async {
    return _guard(() => _p.stat(path), high: high);
  }

  /// Stream a file from the SMB share in chunks.
  ///
  /// This is the preferred way to read large files (e.g. CBZ archives)
  /// without loading them entirely into memory.
  ///
  /// ⚠️ 流式读**不经过全局闸门** ✓ —— 它横跨多次原生调用 ✓，若整段持锁会把其它操作
  /// 卡住任意长时间 ✗。⚠️ 当前项目**未使用**本方法 ✓（属预留 API ✓），
  /// 若将来启用，调用方需自行保证不与其它 SMB 操作并发 ✓。
  Stream<Uint8List> streamFile(
    String path, {
    int chunkSize = 1024 * 1024,
    void Function(int received, int total)? onProgress,
    bool Function()? isCanceled,
  }) {
    return _p.streamFile(
      path,
      chunkSize: chunkSize,
      onProgress: onProgress,
      isCanceled: isCanceled,
    );
  }

  /// Download a file from the SMB share to a local file path.
  Future<void> downloadToFile(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    final localFile = File(localPath);
    await _guard(
      () => _p.downloadToFile(
        remotePath,
        localFile,
        onProgress: onProgress,
        isCanceled: isCanceled,
      ),
      // 下载是长任务 ✓：大文件不能用 25s 的普通操作预算 ✗（否则每次都会误超时 ✓）。
      timeout: _downloadTimeout,
    );
  }

  /// Write data to a file on the SMB share.
  ///
  /// Creates or overwrites the file at [remotePath] with [data].
  /// [onProgress] is called with (bytesSent, totalBytes) during the upload.
  Future<void> writeFile(
    String remotePath,
    Uint8List data, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await _guard(() => _p.writeFile(remotePath, data));
    onProgress?.call(data.length, data.length);
  }

  /// Write data from a stream to a file on the SMB share.
  ///
  /// ⚠️ 与 [streamFile] 同理：**不经过全局闸门** ✓（横跨多次原生调用 ✓），
  /// 当前项目未使用 ✓，启用时需调用方自行保证不并发 ✓。
  Future<void> streamWrite(String remotePath, Stream<Uint8List> stream) async {
    await _p.streamWrite(remotePath, stream);
  }

  /// Recursively create directories on the SMB share.
  ///
  /// [remotePath] is a share-relative path (e.g. `'Comics/Series/Chapter1'`).
  /// Intermediate directories that already exist are silently skipped.
  Future<void> mkdirs(String remotePath) async {
    if (remotePath.isEmpty) return;
    final parts = remotePath.replaceAll('\\', '/').split('/');
    var current = '';
    for (final part in parts) {
      if (part.isEmpty) continue;
      current = current.isEmpty ? part : '$current/$part';
      try {
        await _guard(() => _p.mkdir(current));
      } on Smb2Exception catch (e) {
        // Silently ignore already-exists errors
        if (e.type != Smb2ErrorType.alreadyExists) {
          rethrow;
        }
      }
    }
  }

  /// Reconnect the client (e.g. after a network interruption).
  Future<void> reconnect({bool high = false}) async {
    await disconnect();
    await connect(high: high);
  }
}

/// ⭐ 2026-10-25：**简单的并发限制器** ✓（单客户端内限制同时进行的原生操作数 ✓）。
///
/// 为什么不用全局闸门（用户反馈 ✓）：全局串行 ⇒ 所有读图/封面/扫描排一条队 ✗ ⇒
/// 表现为"像顺序加载、最后一页要等前面全加载完" ✗ —— 完全不是流式阅读 ✓。
/// `dart_smb2` 的连接池有 4 个 worker ✓（本就支持并发 ✓），崩溃真因是"读中途断开"✗，
/// 已规避 ✓ ⇒ 这里只在**单个客户端内**限并发 ✓，不同客户端（阅读器 / 封面）互不阻塞 ✓。
///
/// ⭐ 2026-10-25（P0/P1 ✓）：
/// - **high / low 双队列** ✓：原 `high` 进入 `_guard` 后是死参数 ✗（只有一条 FIFO ✓），
///   前台读图会被后台预取/封面堵住 ✗。现在 release 先唤醒 high ✓。
/// - **inflight + drain()** ✓：记录"原生 Future 真正结束"的数量 ✓（不是 Dart timeout ✓），
///   断开前先等它归零 ✓，避免 `Smb2Pool.disconnect` 5s 后 kill isolate 撞上同步 FFI ✗。
class _OpLimiter {
  _OpLimiter(this.max);

  final int max;

  /// 已发放的信号量名额 ✓（含正在排队等待移交的 ✓）。
  int _current = 0;

  /// 原生 Future **尚未结束** 的数量 ✓（Dart timeout 先返回时仍保持 >0 ✓）。
  int _inflight = 0;

  /// drain 的等待者 ✓（多个 disconnect 共享同一个 Completer ✓）。
  Completer<void>? _drained;

  final List<Completer<void>> _high = [];
  final List<Completer<void>> _low = [];

  /// 是否还有名额在用 / 有等待者 / 原生操作未结束 ✓（共享池空闲回收判断用 ✓）。
  bool get isBusy =>
      _current > 0 || _inflight > 0 || _high.isNotEmpty || _low.isNotEmpty;

  Future<void> acquire({required bool high}) {
    if (_current < max) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    (high ? _high : _low).add(c);
    return c.future;
  }

  void release() {
    final queue = _high.isNotEmpty ? _high : _low;
    if (queue.isNotEmpty) {
      // 名额直接移交给等待者 ✓：_current 不变 ✓。
      queue.removeAt(0).complete();
    } else if (_current > 0) {
      _current--;
    }
  }

  /// 标记一个原生操作开始 ✓（在 `op()` 返回 Future 之后同步调用 ✓）。
  void nativeStarted() {
    _inflight++;
  }

  /// 标记一个原生操作真正结束 ✓（成功/失败/超时后原生 Future 完成 ✓）。
  void nativeFinished() {
    if (_inflight > 0) {
      _inflight--;
    }
    if (_inflight == 0) {
      final c = _drained;
      _drained = null;
      if (c != null && !c.isCompleted) {
        c.complete();
      }
    }
  }

  /// 等在途原生操作归零 ✓，最多 [timeout] ✓（3~5s，由调用方给 ✓）。
  Future<void> drain({required Duration timeout}) async {
    if (_inflight == 0) return;
    final c = _drained ??= Completer<void>();
    await c.future.timeout(timeout, onTimeout: () {});
  }
}
