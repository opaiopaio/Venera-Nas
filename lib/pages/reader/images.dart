part of 'reader.dart';

/// ⭐ 2026-10-25（用户要求 ✓）：**阅读器图片区的底色** ✓
///
/// 背景（用户原话 ✓）：图片背后原先是一层**白底**（主题 surface ✓）⇒
/// 翻页/加载时"像闪光弹一样" ✗。现在可配置 ✓：
/// - `readerBackgroundEnabled == false` ⇒ **透明** ✓ ⇒ 直接露出 App 背景图 ✓
/// - `readerBackgroundColor`：
///   - `system`（默认 ✓）⇒ 跟随主题（浅色白 / 深色黑 ✓，**保持现状观感** ✓）
///   - `transparent` ⇒ 透明 ✓
///   - `#RRGGBB` ⇒ 自定义 ✓
///
/// ⭐ 2026-10-25（用户实测反馈 ✓）：必须**按作用域读**（`readSettingValue` ✓）——
/// 之前直接读全局 `appdata.settings[...]` ✗ ⇒ 开了「漫画特定设置」后，
/// 侧滑里关掉底色**只写了漫画作用域** ✓ 而渲染仍读全局 ✗ ⇒ 表现为"开关动了、画面不变" ✗。
Color readerImageBackgroundColor(
  BuildContext context, {
  String? comicId,
  String? sourceKey,
}) {
  final settings = appdata.settings;
  final useDevice = settings.isDeviceSpecificSettingsEnabled();
  Object? read(String key) =>
      settings.readSettingValue(
        key: key,
        comicId: comicId,
        comicSource: sourceKey,
        useDeviceSettings: useDevice,
      ) ??
      settings[key];

  final enabled = read('readerBackgroundEnabled') != false;
  if (!enabled) return Colors.transparent;
  final raw = (read('readerBackgroundColor') ?? 'system').toString();
  if (raw == 'transparent') return Colors.transparent;
  if (raw.startsWith('#') && raw.length == 7) {
    final value = int.tryParse(raw.substring(1), radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  // system ⇒ 跟随主题 ✓（原本就是这个行为 ✓）
  return Theme.of(context).colorScheme.surface;
}

/// ⭐ 修复（2026-10-25，P1）：**阅读器单页图片的磁盘缓存键** ✓
///
/// 必须与 `ReaderImageProvider.cacheKey`（`foundation/image_provider/reader_image.dart`）
/// **逐字一致**；具体格式由 [readerPageCacheKey] 统一维护 ✓（本函数只转发 ✓）。
/// `sourceKey` 取 `type.comicSource?.key` ✓。
///
/// ⚠️ **不能用 `reader.type.sourceKey`** ✗ —— 它对 SMB 返回 `'smb'` ✓
///（`foundation/comic_type.dart` 的 getter ✓），而 provider 侧 SMB 的 `comicSource == null`
/// ⇒ 真实落盘键里 `sourceKey` 部分是字符串 `null` ✓；用 `'smb'` 拼键会得到 `smb` ✗ ⇒
/// ① 窗口淘汰删不到任何文件（空转 ✓）② 收藏 / 保存图片查不到缓存 ⇒ 报 cache missing ✓。
String _smbPageCacheKey(_ReaderState reader, String imageKey) =>
    readerPageCacheKey(
      imageKey,
      reader.type.comicSource?.key,
      reader.cid,
      reader.eid,
    );

class _ReaderImages extends StatefulWidget {
  const _ReaderImages({super.key});

  @override
  State<_ReaderImages> createState() => _ReaderImagesState();
}

class _ReaderImagesState extends State<_ReaderImages> {
  String? error;

  bool inProgress = false;

  late _ReaderState reader;

  void _savePagesCache(String key, List<String> images) async {
    try {
      var data = utf8.encode(jsonEncode(images));
      await CacheManager().writeCache(key, data);
    } catch (e) {
      Log.warning("Reader", "Failed to save pages cache: $e");
    }
  }

  @override
  void initState() {
    reader = context.reader;
    reader.isLoading = true;
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    ImageDownloader.cancelAllLoadingImages();
    // ⭐ 2026-10-24：退出阅读器 / 切换章节时**断开复用的 SMB 连接** ✓
    //（SMB 读图现在整章共用一条连接 ✓；不主动断开会在 NAS 上留下空闲会话 ✓）。
    ReaderImageProvider.closeSharedSmbClient();
  }

  void _onPagesCacheInvalid() {
    if (!mounted || inProgress) return;
    setState(() {
      error = null;
      reader.isLoading = true;
    });
    context.readerScaffold.update();
  }

  /// Handle jumping to last page when _jumpToLastPageOnLoad is true
  void _handleJumpToLastPage() {
    if (reader._jumpToLastPageOnLoad) {
      reader._page = reader.maxPage;
      reader._jumpToLastPageOnLoad = false;
    }
  }

  void load() async {
    if (inProgress) return;
    inProgress = true;
    if (reader.type == ComicType.local ||
        reader.type == ComicType.smb ||
        (LocalManager().isDownloaded(
          reader.cid,
          reader.type,
          reader.chapter,
          reader.widget.chapters,
        ))) {
      try {
        var images = await LocalManager().getImages(
          reader.cid,
          reader.type,
          reader.chapter,
        );
        if (!mounted) return;
        setState(() {
          reader.images = images;
          reader.isLoading = false;
          inProgress = false;
          _handleJumpToLastPage();
          Future.microtask(() {
            reader.updateHistory();
          });
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          error = e.toString();
          reader.isLoading = false;
          inProgress = false;
        });
      }
    } else {
      var cp = reader.widget.chapters?.ids.elementAtOrNull(reader.chapter - 1);
      // ⭐ 2026-10-26：页列表键也走统一拼装 ✓（前缀与前缀后的字段顺序逐字不变 ✓）。
      var cacheKey = comicPagesListCacheKey(
        reader.type.sourceKey,
        reader.cid,
        reader.eid,
      );

      // Try cache first
      var cacheFile = await CacheManager().findCache(cacheKey);
      if (cacheFile != null) {
        try {
          var cacheData = await cacheFile.readAsBytes();
          var cacheList = (jsonDecode(utf8.decode(cacheData)) as List)
              .cast<String>();
          if (!mounted) return;
          setState(() {
            reader.images = cacheList;
            reader.isLoading = false;
            inProgress = false;
            _handleJumpToLastPage();
            Future.microtask(() {
              reader.updateHistory();
            });
          });
          context.readerScaffold.update();
          return;
        } catch (_) {
          // Cache corrupted, fall through to network request
        }
      }

      var res = await reader.type.comicSource!.loadComicPages!(
        reader.widget.cid,
        cp,
      );
      if (!mounted) return;
      if (res.error) {
        setState(() {
          error = res.errorMessage;
          reader.isLoading = false;
          inProgress = false;
        });
      } else {
        // Save to cache in background
        _savePagesCache(cacheKey, res.data);
        setState(() {
          reader.images = res.data;
          reader.isLoading = false;
          inProgress = false;
          _handleJumpToLastPage();
          Future.microtask(() {
            reader.updateHistory();
          });
        });
      }
    }
    if (!mounted) return;
    context.readerScaffold.update();
  }

  @override
  Widget build(BuildContext context) {
    if (reader.isLoading) {
      load();
      return const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      return GestureDetector(
        onTap: () {
          context.readerScaffold.openOrClose();
        },
        child: SizedBox.expand(
          child: NetworkError(
            message: error!,
            retry: () {
              setState(() {
                reader.isLoading = true;
                error = null;
              });
            },
          ),
        ),
      );
    } else {
      if (reader.mode.isGallery) {
        var showComments =
            appdata.settings.getReaderSetting(
              reader.cid,
              reader.type.sourceKey,
              'showChapterComments',
            ) ==
            true;
        var showCommentsAtEnd =
            appdata.settings.getReaderSetting(
              reader.cid,
              reader.type.sourceKey,
              'showChapterCommentsAtEnd',
            ) ==
            true;
        return _GalleryMode(
          key: Key(
            '${reader.mode.key}_${reader.imagesPerPage}_${showComments}_${showCommentsAtEnd}_${appdata.settings['showComments']}',
          ),
        );
      } else {
        return _ContinuousMode(key: Key(reader.mode.key));
      }
    }
  }
}

class _GalleryMode extends StatefulWidget {
  const _GalleryMode({super.key});

  @override
  State<_GalleryMode> createState() => _GalleryModeState();
}

class _GalleryModeState extends State<_GalleryMode>
    implements _ImageViewController {
  late PageController controller;

  /// ⭐ 2026-10-24：**两级预取防抖** ✓
  /// - [  _neighborDebounce ] 相邻页（`AppMotion.short` = 200ms ✓）：**落盘 + 解码** ✓
  ///   ⇒ 翻下一页**不再闪** ✓（用户实测：只落盘不解码时"当前页很快，但翻下一页闪" ✗）
  /// - [  _prefetchDebounce ] 远一点的页（`AppMotion.medium` = 300ms ✓）：**只落盘、不解码** ✓
  /// 两者都会在"连续翻页"时不断重置 ✓ ⇒ **狂翻期间一次预取都不发** ✓（全部带宽给当前页 ✓）。
  Timer? _neighborDebounce;

  Timer? _prefetchDebounce;

  int get preCacheCount {
    final configured =
        appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'preloadImageCount',
        ) ??
        0;
    // ⭐ 2026-10-25（用户反馈 ✓）：**SMB / NAS 的预加载按设置值的「一半」** ✓ ——
    // 云端读图每页都要走网络 ✓，比本地文件慢得多 ✓；不同设备（电脑 / 平板 / 路由器性能 ✓）
    // 差异也大 ✓ ⇒ 照搬设置值会把带宽与队列占满 ✗ ⇒ 快速翻两页仍然闪 ✗。
    // 减半后：相邻页仍解码（翻页不闪 ✓），排队压力明显下降 ✓。
    if (reader.type == ComicType.smb) {
      if (configured <= 1) return configured;
      return (configured / 2).ceil();
    }
    return configured;
  }

  /// ⭐ 2026-10-25：**解码窗口大小** ✓ —— 狂翻时临时缩到 2 页 ✓。
  ///
  /// 两个预取通道（相邻 / 远页）**必须共用同一口径** ✓，否则窗口边界算不一致 ⇒
  /// 两通道覆盖范围重叠 ✗（同一批页被请求两次 ✓，白占 SMB 带宽 ✓）。
  int get _decodeAhead {
    final configured = preCacheCount;
    if (_fastFlip && configured > 2) return 2;
    return configured;
  }

  var photoViewControllers = <int, PhotoViewController>{};

  /// ⭐ 2026-10-25：**已从 [photoViewControllers] 摘下、但还不能立刻释放的 controller** ✓。
  /// `onPageChanged` 里同帧 `PhotoViewGallery` 仍可能持有它们 ✗ ⇒ 立刻 `dispose()` 会
  /// use-after-dispose ✓（`reset()` / `updateMultiple()` 会往已关闭的 StreamController 写 ✓）。
  /// 故先 `reset()` 收掉缩放/位置状态并暂存 ✓，到本 State 的 `dispose` 再统一释放 ✓。
  final List<PhotoViewController> _retiredControllers = [];

  late _ReaderState reader;

  /// ⭐ 修复（2026-10-25，P2）：**显式持有上级 `_ReaderImagesState`** ✓ ——
  /// 原先 `_createImageProviderFromKey` 用 `visitAncestorElements` 反查（**恒失效** ✗），
  /// 于是 `onLoadFailed` 恒为 null ⇒ 图片加载失败不再触发"页面列表失效 ⇒ 重载" ✓。
  /// 现在 initState 里取一次 ✓，创建 provider 时显式传下去 ✓（不再依赖 element 树反查 ✓）。
  _ReaderImagesState? imagesState;

  bool get showChapterCommentsAtEnd {
    if (appdata.settings['showComments'] != true) return false;
    if (reader.mode != ReaderMode.galleryLeftToRight &&
        reader.mode != ReaderMode.galleryRightToLeft) {
      return false;
    }
    if (reader.widget.chapters == null) return false;
    var source = ComicSource.find(reader.type.sourceKey);
    if (source?.chapterCommentsLoader == null) return false;
    return appdata.settings.getReaderSetting(
              reader.cid,
              reader.type.sourceKey,
              'showChapterComments',
            ) ==
            true &&
        appdata.settings.getReaderSetting(
              reader.cid,
              reader.type.sourceKey,
              'showChapterCommentsAtEnd',
            ) ==
            true;
  }

  int get totalImagePages {
    return !reader.showSingleImageOnFirstPage()
        ? (reader.images!.length / reader.imagesPerPage).ceil()
        : 1 + ((reader.images!.length - 1) / reader.imagesPerPage).ceil();
  }

  int get totalPages => reader.totalPages;

  bool isChapterCommentsPage(int pageIndex) {
    return showChapterCommentsAtEnd && pageIndex == totalImagePages + 1;
  }

  var imageStates = <State<ComicImage>>{};

  bool isLongPressing = false;

  int fingers = 0;

  @override
  void initState() {
    reader = context.reader;
    imagesState = context.findAncestorStateOfType<_ReaderImagesState>();
    controller = PageController(initialPage: reader.page);
    reader._imageViewController = this;
    Future.microtask(() {
      if (!mounted) return;
      context.readerScaffold.setFloatingButton(0);
    });
    super.initState();
  }

  // ⭐ AP1-A3（审计 ✓）：本 State 原先**没有 `dispose`** ✗ → `PageController`（initState 内自建 ✓）
  // 与 `photoViewControllers` 里的 `PhotoViewController` 全部**泄漏** ✓（滚动位置/手势/动画状态常驻 ✓）。
  // ⚠️ 只在 `State.dispose` 释放 ✓：**不要**在 `onPageChanged` 的 `remove(key)` 处 dispose ✗
  //（那之后同帧仍会使用该 controller ✓ → 会 use-after-dispose ✓）。
  @override
  void dispose() {
    _neighborDebounce?.cancel();
    _neighborDebounce = null;
    _prefetchDebounce?.cancel();
    _prefetchDebounce = null;
    controller.dispose();
    for (final c in photoViewControllers.values) {
      c.dispose();
    }
    photoViewControllers.clear();
    // ⭐ 2026-10-25：`onPageChanged` 摘下、延迟释放的 controller 在这里统一收尾 ✓。
    for (final c in _retiredControllers) {
      c.dispose();
    }
    _retiredControllers.clear();
    // ⭐ 修复（2026-10-25，P1）：**把自己从 reader 上摘掉** ✗→✓ ——
    // 原先 `reader._imageViewController` 只被赋值、从不置空 ✗ ⇒ 切章时旧模式的 State
    // 已 dispose ✓ 但全局引用仍指向它 ✗ ⇒ 切章期的手势 / 键盘 / 保存图片会操作**已释放的
    // controller** ✓（`reset()`、已关闭的 StreamController ⇒ 抛异常 ✓）。
    // 只清"自己挂上的那个" ✓（identical ✓）—— 新模式可能已在 initState 里先挂上 ✓。
    if (identical(reader._imageViewController, this)) {
      reader._imageViewController = null;
    }
    super.dispose();
  }

  /// Get the range of images for the given page. [page] is 1-based.
  (int start, int end) getPageImagesRange(int page) {
    var imagesPerPage = reader.imagesPerPage;
    if (reader.showSingleImageOnFirstPage()) {
      if (page == 1) {
        return (0, 1);
      } else {
        int startIndex = (page - 2) * imagesPerPage + 1;
        int endIndex = math.min(
          startIndex + imagesPerPage,
          reader.images!.length,
        );
        return (startIndex, endIndex);
      }
    } else {
      int startIndex = (page - 1) * imagesPerPage;
      int endIndex = math.min(
        startIndex + imagesPerPage,
        reader.images!.length,
      );
      return (startIndex, endIndex);
    }
  }

  /// 获取当前页的图片索引范围。无图片时返回 null（如评论页或图片未加载）。
  (int, int)? getCurrentPageImageRange() {
    if (reader.images == null || reader.images!.isEmpty) {
      return null;
    }
    // 评论页没有图片，按公式算出的 startIndex 会越界，导致收藏时崩溃
    if (isChapterCommentsPage(reader.page)) {
      return null;
    }
    var (startIndex, endIndex) = getPageImagesRange(reader.page);
    if (startIndex >= reader.images!.length) {
      return null;
    }
    return (startIndex, endIndex);
  }

  /// ⭐ 2026-10-24：**防抖预取** ✓ —— `cache()` 在每次页面构建时都会被调用 ✓，
  /// 快速滚轮翻页时若立刻预取，会把当前页正在等的 SMB 带宽/连接占满 ✗
  /// （用户实测：快速滑百来页会转圈 ✓；停下后还会因后台预取解码而"闪两下" ✗）。
  /// 现在：**每次调用都把预取推迟一个令牌时长** ✓ —— 连续翻页会不断重置计时器 ✓
  /// ⇒ 只有"停下来"才真正预取 ✓。
  void cache(int startPage) {
    // ① 相邻页：短防抖 ⇒ **落盘 + 给"下一页"解码** ✓（这是"翻页不闪"的关键 ✓）。
    _neighborDebounce?.cancel();
    _neighborDebounce = Timer(AppMotion.short, () {
      if (!mounted) return;
      _cacheNeighborsNow(startPage);
    });
    // ② 其余页：长防抖 ⇒ **只落盘** ✓（解码仍只发生在真正显示时 ✓）。
    _prefetchDebounce?.cancel();
    _prefetchDebounce = Timer(AppMotion.medium, () {
      if (!mounted) return;
      _cacheNow(startPage);
    });
  }

  /// ⭐ 相邻页预取（**2026-10-25 按用户设想重写 ✓**：滑动窗口 ✓）
  ///
  /// 用户设想（原文含义 ✓）：
  /// - 永远**优先当前页** ✓（不被其它任务挤占 ✓）
  /// - 设置 10 ⇒ **前 5 页直接解码** ✓（翻到就显示 ✓ 不闪 ✗）
  /// - **后 5 页只落盘** ✓（不解码 ✓，省内存 ✓）
  /// - 往后翻一页 ⇒ **落盘的下一页开始解码** ✓（始终维持 5 页"已解码"✓），
  ///   同时**再往后补一页落盘** ✓ ⇒ 窗口整体前移 ✓
  /// - ⭐ **限制窗口总量** ✓：超出后就**清掉更早的页**（先清解码/落盘的那些 ✓）
  ///
  /// 说明：`preCacheCount` 对 SMB 已**减半** ✓（见 getter ✓）⇒ 设置 10 ⇒ 这里 =
  /// `decodeAhead = 5` ✓、`diskAhead = 5` ✓，合计正好 10 页窗口 ✓。
  void _cacheNeighborsNow(int startPage) {
    // ⭐ 2026-10-25（用户要求 ✓）：**按翻页速度自适应** ✓ ——
    // 连续快速翻页时（< 500ms 一页 ✓）把"解码区"临时缩到 2 页 ✓：
    // 解码很占内存/CPU ✓，狂翻时用户根本来不及看 ✓ ⇒ 省下来给当前页 ✓（当前页永远最高优先 ✓）。
    // 一旦停稳（> 500ms ✓）⇒ 恢复成正常解码区（设置的一半 ✓）。
    final now = DateTime.now();
    final lastFlip = _lastFlipAt;
    // 阈值取令牌 `AppMotion.long`（400ms ✓）—— 硬编码时长会被外观守卫拦下 ✗。
    _fastFlip = lastFlip != null && now.difference(lastFlip) < AppMotion.long;
    _lastFlipAt = now;

    final configured = preCacheCount;
    final decodeAhead = _decodeAhead;
    final diskAhead = configured; // 再往后 configured 页只落盘 ✓

    // ① 已解码窗口：上一页 ~ 当前页 + decodeAhead ✓
    for (int offset = -1; offset <= decodeAhead; offset++) {
      final page = startPage + offset;
      if (page <= 0 ||
          page > totalPages ||
          page == startPage ||
          isChapterCommentsPage(page)) {
        continue;
      }
      _cachePage(page, true); // 落盘 + 解码 ✓
    }

    // ② 只落盘窗口：decodeAhead+1 ~ decodeAhead+diskAhead ✓
    for (
      int offset = decodeAhead + 1;
      offset <= decodeAhead + diskAhead;
      offset++
    ) {
      final page = startPage + offset;
      if (page <= 0 || page > totalPages || isChapterCommentsPage(page)) {
        continue;
      }
      _cachePage(page, false); // 只落盘 ✓
    }

    // ③ 窗口总量上限：把**更早的页**从磁盘缓存里清掉 ✓（用户要的"最大缓存" ✓）
    _trimDiskCacheWindow(startPage, decodeAhead + diskAhead);
  }

  /// 记录"已落过盘的页码" ✓ —— 用于按窗口上限淘汰窗口外的旧页 ✓。
  ///
  /// ⭐ 2026-10-25：**改用 `Set<int>`** ✗→✓ —— 原先用 `List<int>` ✓ 且在
  /// `_cachePage` 的**按图循环**里 `add(page)` ✗ ⇒ 一页多图时同一页会被重复记账 ✓
  /// ⇒ ① 窗口长度虚高、淘汰过早 ✗ ② 同一页被 `_deletePageDiskCache` 重复调用 ✓。
  /// `Set` 天然按页去重 ✓，语义就是"这个页落过盘" ✓。
  final Set<int> _diskWindowPages = {};

  /// ⭐ 2026-10-25：上次翻页时间 / 是否处于"狂翻"状态 ✓（自适应预载用 ✓）。
  DateTime? _lastFlipAt;
  bool _fastFlip = false;

  /// ⭐ 清掉窗口外的旧页磁盘缓存 ✓（解码内存由 `ImageCache` 的容量上限兜底 ✓）。
  ///
  /// ⭐ 2026-10-25：**改为按页范围淘汰** ✗→✓ —— 原先按"入队顺序 + 长度截断" ✗：
  /// 往回翻 / 跳页后顺序与页号脱钩 ⇒ 会淘汰**当前窗口内**的页、反而留下远处的页 ✓。
  /// 现在只保留 `[startPage-2, startPage+windowSize+2]` ✓，范围外一律清掉 ✓。
  void _trimDiskCacheWindow(int startPage, int windowSize) {
    final keepFrom = startPage - 2; // 往回留 2 页余量 ✓（来回翻不重读 ✓）
    final keepTo = startPage + windowSize + 2;
    final stale = _diskWindowPages
        .where((p) => p < keepFrom || p > keepTo)
        .toList();
    for (final page in stale) {
      _diskWindowPages.remove(page);
      _deletePageDiskCache(page);
    }
  }

  /// 删除某一页的**磁盘缓存** ✓（只清 SMB 页 ✓，本地页走系统缓存 ✓）。
  void _deletePageDiskCache(int page) {
    if (page <= 0 || page > totalPages) return;
    var (startIndex, endIndex) = getPageImagesRange(page);
    for (int i = startIndex; i < endIndex; i++) {
      final key = reader.images!.elementAtOrNull(i);
      if (key == null || !key.startsWith('smb://')) continue;
      // ⭐ 键必须与 provider 侧一致 ✓（见 `_smbPageCacheKey` 注释 ✓）；
      // 原先用 `reader.type.sourceKey` 拼出 `@smb@` ✗ ⇒ 永远删不到真实缓存 ✓。
      CacheManager().delete(_smbPageCacheKey(reader, key));
    }
  }

  void _cacheNow(int startPage) {
    // ⭐ 修复（2026-10-25，P2）：**两个预取通道不得重叠** ✗→✓ ——
    // 相邻通道（`_cacheNeighborsNow`）已覆盖 `startPage-1 … startPage+decodeAhead` ✓；
    // 本通道（长防抖、只落盘）原先从 `startPage-1` 起算 ✗ ⇒ 同一批页被请求两次 ✓
    //（重复落盘 / 重复解码，白占 SMB 带宽 ✓）。现在**从 `decodeAhead+1` 起算** ✓，
    // 只补"更远、仅落盘"的那一截 ✓，上界与相邻通道的 ② 保持一致 ✓。
    final decodeAhead = _decodeAhead;
    final diskAhead = preCacheCount;
    for (
      int offset = decodeAhead + 1;
      offset <= decodeAhead + diskAhead;
      offset++
    ) {
      final page = startPage + offset;
      if (page <= 0 || page > totalPages || isChapterCommentsPage(page)) {
        continue;
      }
      _cachePage(page, false);
    }
  }

  void _cachePage(int page, bool shouldPreCache) {
    if (isChapterCommentsPage(page)) return;
    var (startIndex, endIndex) = getPageImagesRange(page);
    var hasSmbImage = false;
    for (int i = startIndex; i < endIndex; i++) {
      final key = reader.images!.elementAtOrNull(i);
      final isSmb = key?.startsWith('smb://') ?? false;
      // ⭐ 2026-10-25（用户设想 ✓）：SMB 页**也按窗口解码** ✓ ——
      // 之前一律"只落盘不解码" ✗ ⇒ 翻页仍要等解码 ⇒ 闪 ✗；
      // 现在窗口内前 N 页直接解码 ✓（翻到即显示 ✓），窗口外只落盘 ✓。
      if (shouldPreCache) {
        _precacheImage(i + 1, context);
      } else {
        _preDownloadImage(i + 1, context);
      }
      if (isSmb) {
        hasSmbImage = true;
      }
    }
    // ⭐ 2026-10-25：按**页**记账一次 ✓（不再在按图循环里重复 add ✓，见 `_diskWindowPages` 注释 ✓）。
    if (hasSmbImage) {
      _diskWindowPages.add(page);
    }
  }

  Widget _buildChapterCommentsPage() {
    var source = ComicSource.find(reader.type.sourceKey);
    var chapters = reader.widget.chapters;
    if (source == null || chapters == null) return const SizedBox();
    var chapterIndex = reader.chapter - 1;
    return _EmbeddedChapterCommentsPage(
      comicId: reader.cid,
      epId: chapters.ids.elementAt(chapterIndex),
      source: source,
      comicTitle: reader.widget.name,
      chapterTitle: chapters.titles.elementAt(chapterIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        fingers++;
      },
      onPointerUp: (event) {
        fingers--;
      },
      onPointerCancel: (event) {
        fingers--;
      },
      onPointerMove: (event) {
        if (isLongPressing) {
          // ⭐ 修复（2026-10-25，P1）：**判空** ✗→✓ —— 长按期间刚切页/进入评论页时
          // 该页的 controller 已不在 map 里 ✓，原先 `!` 强解包会空指针崩溃 ✗。
          final controller = photoViewControllers[reader.page];
          if (controller != null) {
            controller.updateMultiple(
              position: controller.position + event.delta,
            );
          }
        }
      },
      child: PhotoViewGallery.builder(
        backgroundDecoration: BoxDecoration(
          color: readerImageBackgroundColor(
            context,
            comicId: reader.cid,
            sourceKey: reader.type.sourceKey,
          ),
        ),
        reverse: reader.mode == ReaderMode.galleryRightToLeft,
        scrollDirection: reader.mode == ReaderMode.galleryTopToBottom
            ? Axis.vertical
            : Axis.horizontal,
        itemCount: totalPages + 2,
        builder: (BuildContext context, int index) {
          if (index == 0 || index == totalPages + 1) {
            return PhotoViewGalleryPageOptions.customChild(
              child: const SizedBox(),
            );
          } else if (isChapterCommentsPage(index)) {
            return PhotoViewGalleryPageOptions.customChild(
              child: _buildChapterCommentsPage(),
              // 评论页非图片，禁用缩放手势，防止整页被双指缩放
              disableGestures: true,
              initialScale: PhotoViewComputedScale.contained * 1.0,
              minScale: PhotoViewComputedScale.contained * 1.0,
              maxScale: PhotoViewComputedScale.contained * 1.0,
            );
          } else {
            var (startIndex, endIndex) = getPageImagesRange(index);
            List<String> pageImages = reader.images!.sublist(
              startIndex,
              endIndex,
            );

            cache(index);

            photoViewControllers[index] ??= PhotoViewController();

            if (reader.imagesPerPage == 1 || pageImages.length == 1) {
              return PhotoViewGalleryPageOptions(
                filterQuality: FilterQuality.medium,
                controller: photoViewControllers[index],
                imageProvider: _createImageProviderFromKey(
                  pageImages[0],
                  context,
                  startIndex + 1,
                  // ⭐ 2026-10-25：显式传"页面列表失效"回调 ✓（原先靠 ancestor 反查、恒失效 ✗）。
                  onLoadFailed: imagesState?._onPagesCacheInvalid,
                ),
                fit: BoxFit.contain,
                errorBuilder: (_, error, s, retry) {
                  return NetworkError(message: error.toString(), retry: retry);
                },
              );
            }

            final viewportSize = MediaQuery.of(context).size;
            return PhotoViewGalleryPageOptions.customChild(
              childSize: viewportSize,
              controller: photoViewControllers[index],
              minScale: PhotoViewComputedScale.contained * 1.0,
              maxScale: PhotoViewComputedScale.covered * 10.0,
              child: buildPageImages(pageImages, startIndex),
            );
          }
        },
        pageController: controller,
        loadingBuilder: (context, event) {
          return PhotoView.customChild(
            childSize: MediaQuery.of(context).size,
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained * 1.0,
            maxScale: PhotoViewComputedScale.covered * 10.0,
            backgroundDecoration: BoxDecoration(
              color: readerImageBackgroundColor(
                context,
                comicId: reader.cid,
                sourceKey: reader.type.sourceKey,
              ),
            ),
            child: Center(
              child: SizedBox(
                width: 20.0,
                height: 20.0,
                child: CircularProgressIndicator(
                  backgroundColor: context.colorScheme.surfaceContainerHigh,
                  value: event == null || event.expectedTotalBytes == null
                      ? null
                      : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                ),
              ),
            ),
          );
        },
        onPageChanged: (i) {
          if (i == 0) {
            if (reader.isFirstChapterOfGroup ||
                !reader.toPrevChapter(toLastPage: true)) {
              controller.jumpToPage(1);
            }
          } else if (i == totalPages + 1) {
            if (reader.isLastChapterOfGroup || !reader.toNextChapter()) {
              controller.jumpToPage(totalPages);
            }
          } else {
            // ⭐ 修复（2026-10-10 全量代码审查 ✓）：**用户手势应当打断在途动画** ✗→✓ ——
            // 否则 `setPage` 的早退判据会把"动画途中拖拽/滑条到达的页码"静默丢弃 ✗
            //（表现为 `_page` 与屏幕实际显示页暂时不一致 ✓）。
            reader.cancelPageAnimation();
            reader.setPage(i);
            context.readerScaffold.update();
            // Auto close toolbar when entering chapter comments page
            if (isChapterCommentsPage(i) && context.readerScaffold.isOpen) {
              context.readerScaffold.openOrClose();
            }
          }
          // ⭐ 修复（2026-10-25，P2）：**相邻页 controller 不在这里 dispose** ✗→✓ ——
          // 同帧 `PhotoViewGallery` 仍可能持有并使用它们 ✓，`dispose()` 之后再被
          // `updateMultiple` / `reset` 调用就会往**已关闭的 StreamController** 写 ⇒ 抛异常 ✓
          //（use-after-dispose ✓）。现在：只从 map 里摘下 ✓ + `reset()` 收掉缩放/位置状态 ✓，
          // 真正的 `dispose()` 留到本 State 的 `dispose` 统一处理 ✓。
          for (var key in photoViewControllers.keys.toList()) {
            if (key == i) continue;
            final oldController = photoViewControllers.remove(key);
            if (oldController == null) continue;
            oldController.reset();
            _retiredControllers.add(oldController);
          }
        },
      ),
    );
  }

  Widget buildPageImages(List<String> images, int startIndex) {
    Axis axis = (reader.mode == ReaderMode.galleryTopToBottom)
        ? Axis.vertical
        : Axis.horizontal;

    bool reverse = reader.mode == ReaderMode.galleryRightToLeft;
    if (reverse) {
      images = images.reversed.toList();
    }

    List<Widget> imageWidgets;

    if (images.length == 2) {
      imageWidgets = [
        Expanded(
          child: ComicImage(
            width: double.infinity,
            height: double.infinity,
            image: _createImageProviderFromKey(
              images[0],
              context,
              startIndex + 1,
              // ⭐ 2026-10-25：显式传回调 ✓（见 `_createImageProviderFromKey` 注释 ✓）。
              onLoadFailed: imagesState?._onPagesCacheInvalid,
            ),
            fit: BoxFit.contain,
            alignment: axis == Axis.vertical
                ? Alignment.bottomCenter
                : Alignment.centerRight,
            onInit: (state) => imageStates.add(state),
            onDispose: (state) => imageStates.remove(state),
          ),
        ),
        Expanded(
          child: ComicImage(
            width: double.infinity,
            height: double.infinity,
            image: _createImageProviderFromKey(
              images[1],
              context,
              startIndex + 2,
              onLoadFailed: imagesState?._onPagesCacheInvalid,
            ),
            fit: BoxFit.contain,
            alignment: axis == Axis.vertical
                ? Alignment.topCenter
                : Alignment.centerLeft,
            onInit: (state) => imageStates.add(state),
            onDispose: (state) => imageStates.remove(state),
          ),
        ),
      ];
    } else {
      imageWidgets = images.map((imageKey) {
        startIndex++;
        ImageProvider imageProvider = _createImageProviderFromKey(
          imageKey,
          context,
          startIndex,
          onLoadFailed: imagesState?._onPagesCacheInvalid,
        );
        return Expanded(
          child: ComicImage(
            image: imageProvider,
            fit: BoxFit.contain,
            onInit: (state) => imageStates.add(state),
            onDispose: (state) => imageStates.remove(state),
          ),
        );
      }).toList();
    }

    return axis == Axis.vertical
        ? Column(children: imageWidgets)
        : Row(children: imageWidgets);
  }

  @override
  Future<void> animateToPage(int page) {
    if ((page - controller.page!.round()).abs() > 1) {
      controller.jumpToPage(page > controller.page! ? page - 1 : page + 1);
    }
    return controller.animateToPage(
      page,
      duration: AppMotion.short,
      curve: Curves.ease,
    );
  }

  @override
  void toPage(int page) {
    controller.jumpToPage(page);
  }

  @override
  void handleDoubleTap(Offset location) {
    if (appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'quickCollectImage',
        ) ==
        'DoubleTap') {
      context.readerScaffold.addImageFavorite();
      return;
    }
    // ⭐ 修复（2026-10-25，P1）：**三个入口都必须先判空** ✗→✓ ——
    // 评论页没有图片 controller ✓；切页/切章瞬间该页 controller 也可能已从 map 摘下 ✓
    // ⇒ 原先的 `photoViewControllers[reader.page]!` 会空指针崩溃 ✗。
    if (reader.isOnChapterCommentsPage) return;
    final controller = photoViewControllers[reader.page];
    if (controller == null) return;
    controller.onDoubleClick?.call();
  }

  @override
  void handleLongPressDown(Offset location) {
    if (!appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'enableLongPressToZoom',
        ) ||
        fingers != 1) {
      return;
    }
    // 判空（评论页 / 切页瞬间无 controller ✓）+ `getInitialScale` 为空则放弃缩放 ✓：
    // `getInitialScale` 由页面首次 build 时注入 ✓，未注入时 `!` 强解包必崩 ✗。
    if (reader.isOnChapterCommentsPage) return;
    var photoViewController = photoViewControllers[reader.page];
    if (photoViewController == null) return;
    var initialScale = photoViewController.getInitialScale?.call();
    if (initialScale == null) return;
    double target = initialScale * 1.75;
    var size = reader.size;
    Offset zoomPosition;
    if (appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'longPressZoomPosition',
        ) !=
        'center') {
      zoomPosition = Offset(
        size.width / 2 - location.dx,
        size.height / 2 - location.dy,
      );
    } else {
      zoomPosition = Offset(0, 0);
    }
    photoViewController.animateScale?.call(target, zoomPosition);
    isLongPressing = true;
  }

  @override
  void handleLongPressUp(Offset location) {
    if (!appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'enableLongPressToZoom',
        ) ||
        !isLongPressing) {
      return;
    }
    // 同 `handleLongPressDown`：判空 + 初始缩放为空则直接收尾 ✓（不崩 ✓）。
    if (reader.isOnChapterCommentsPage) return;
    var photoViewController = photoViewControllers[reader.page];
    if (photoViewController == null) return;
    var initialScale = photoViewController.getInitialScale?.call();
    if (initialScale == null) {
      isLongPressing = false;
      return;
    }
    photoViewController.animateScale?.call(initialScale);
    isLongPressing = false;
  }

  Timer? keyRepeatTimer;

  @override
  void handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      if (!reader.toPage(reader.page + 1) && !reader.isLastChapterOfGroup) {
        reader.toNextChapter();
      }
      return;
    }
    bool? forward;
    if (reader.mode == ReaderMode.galleryLeftToRight &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      forward = true;
    } else if (reader.mode == ReaderMode.galleryRightToLeft &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      forward = true;
    } else if (reader.mode == ReaderMode.galleryTopToBottom &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      forward = true;
    } else if (reader.mode == ReaderMode.galleryTopToBottom &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      forward = false;
    } else if (reader.mode == ReaderMode.galleryLeftToRight &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      forward = false;
    } else if (reader.mode == ReaderMode.galleryRightToLeft &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      forward = false;
    }
    if (event is KeyDownEvent) {
      if (keyRepeatTimer != null) {
        keyRepeatTimer!.cancel();
        keyRepeatTimer = null;
      }
      if (forward == true) {
        reader.toPage(reader.page + 1);
      } else if (forward == false) {
        reader.toPage(reader.page - 1);
      }
    }
    if (event is KeyRepeatEvent && keyRepeatTimer == null) {
      keyRepeatTimer = Timer.periodic(
        reader.enablePageAnimation(reader.cid, reader.type)
            ? AppMotion.short
            : const Duration(milliseconds: 50),
        (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          } else if (forward == true) {
            reader.toPage(reader.page + 1);
          } else if (forward == false) {
            reader.toPage(reader.page - 1);
          }
        },
      );
    }
    if (event is KeyUpEvent && keyRepeatTimer != null) {
      keyRepeatTimer!.cancel();
      keyRepeatTimer = null;
    }
  }

  @override
  bool handleOnTap(Offset location) {
    return false;
  }

  @override
  Future<Uint8List?> getImageByOffset(Offset offset) async {
    var imageKey = getImageKeyByOffset(offset);
    if (imageKey == null) return null;
    if (imageKey.startsWith("file://")) {
      return await File(imageKey.substring(7)).readAsBytes();
    } else {
      // ⭐ 修复（2026-10-09）：**去掉硬 `!` 强解包** —— 缓存被清理/过期时 findCache 返回 null，
      // 原写法会空指针崩溃。现改为显式抛错，交由 ImageProvider 的失败路径处理（显示失败/按需重试）；
      // **正常命中缓存的路径行为完全不变**（同一 key、同一 readAsBytes）。
      // ⭐ 修复（2026-10-25，P1）：键改走 `_smbPageCacheKey` ✓ —— 原先用 `type.sourceKey`
      // 拼键 ✗，对 SMB 会得到 `@smb@` 而真实键是 `@null@` ⇒ 收藏/保存恒报 cache missing ✓。
      final cached = await CacheManager().findCache(
        _smbPageCacheKey(reader, imageKey),
      );
      if (cached == null || !cached.existsSync()) {
        throw Exception("Reader image cache missing: $imageKey");
      }
      return cached.readAsBytes();
    }
  }

  @override
  String? getImageKeyByOffset(Offset offset) {
    var range = getCurrentPageImageRange();
    if (range == null) return null;

    var (startIndex, endIndex) = range;
    int actualImageCount = endIndex - startIndex;

    if (actualImageCount <= 0) {
      return null;
    }

    if (actualImageCount == 1) {
      return reader.images![startIndex];
    }

    for (var imageState in imageStates) {
      if ((imageState as _ComicImageState).containsPoint(offset)) {
        var imageKey =
            (imageState.widget.image as ReaderImageProvider).imageKey;
        int index = reader.images!.indexOf(imageKey);
        if (index >= startIndex && index < endIndex) {
          return imageKey;
        }
      }
    }

    return reader.images![startIndex];
  }
}

const Set<PointerDeviceKind> _kTouchLikeDeviceTypes = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.mouse,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

const double _kChangeChapterOffset = 160;

class _ContinuousMode extends StatefulWidget {
  const _ContinuousMode({super.key});

  @override
  State<_ContinuousMode> createState() => _ContinuousModeState();
}

class _ContinuousModeState extends State<_ContinuousMode>
    implements _ImageViewController {
  late _ReaderState reader;

  /// ⭐ 修复（2026-10-25，P2）：显式持有上级 `_ReaderImagesState` ✓，
  /// 用于把"页面列表失效"回调显式传给 `ImageProvider` ✓（原先 ancestor 反查恒失效 ✗）。
  _ReaderImagesState? imagesState;

  var itemScrollController = ItemScrollController();
  var itemPositionsListener = ItemPositionsListener.create();
  var photoViewController = PhotoViewController();
  ScrollController? _scrollController;

  ScrollController get scrollController => _scrollController!;

  var isCTRLPressed = false;
  static var _isMouseScrolling = false;
  var fingers = 0;
  bool disableScroll = false;

  late List<bool> cached;

  int get preCacheCount {
    final configured =
        appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'preloadImageCount',
        ) ??
        0;
    // ⭐ 2026-10-25（用户反馈 ✓）：**SMB / NAS 的预加载按设置值的「一半」** ✓ ——
    // 云端读图每页都要走网络 ✓，比本地文件慢得多 ✓；不同设备（电脑 / 平板 / 路由器性能 ✓）
    // 差异也大 ✓ ⇒ 照搬设置值会把带宽与队列占满 ✗ ⇒ 快速翻两页仍然闪 ✗。
    // 减半后：相邻页仍解码（翻页不闪 ✓），排队压力明显下降 ✓。
    if (reader.type == ComicType.smb) {
      if (configured <= 1) return configured;
      return (configured / 2).ceil();
    }
    return configured;
  }

  /// Whether the user was scrolling the page.
  /// The gesture detector has a delay to detect tap event.
  /// To handle the tap event, we need to know if the user was scrolling before the delay.
  bool delayedIsScrolling = false;

  var imageStates = <State<ComicImage>>{};

  void delayedSetIsScrolling(bool value) {
    Future.delayed(AppMotion.medium, () => delayedIsScrolling = value);
  }

  bool prepareToPrevChapter = false;
  bool prepareToNextChapter = false;
  bool jumpToNextChapter = false;
  bool jumpToPrevChapter = false;

  bool isZoomedIn = false;
  bool isLongPressing = false;

  @override
  void initState() {
    reader = context.reader;
    imagesState = context.findAncestorStateOfType<_ReaderImagesState>();
    reader._imageViewController = this;
    itemPositionsListener.itemPositions.addListener(onPositionChanged);
    cached = List.filled(reader.maxPage + 2, false);
    Future.delayed(
      const Duration(milliseconds: 100),
      () => cacheImages(reader.page),
    );
    super.initState();
  }

  @override
  void dispose() {
    // ⭐ 修复（2026-10-25，P2）：**补全释放** ✗→✓ —— 原先只移除一个监听 ✓，
    // `photoViewController` / 滚动监听 / reader 上的引用全部漏释放 ✗
    // ⇒ 切章后仍常驻 + `_imageViewController` 指向已 dispose 的 State ✓（同 gallery ✓）。
    // ⚠️ `itemPositions` 在接口上是 `ValueListenable`（没有 `dispose` ✓），
    // 随列表一起回收 ✓ ⇒ 这里只摘监听 ✓。
    itemPositionsListener.itemPositions.removeListener(onPositionChanged);
    _scrollController?.removeListener(onScroll);
    _scrollController = null;
    photoViewController.dispose();
    // 只清"自己挂上的那个" ✓（新模式可能已先挂上 ✓）。
    if (identical(reader._imageViewController, this)) {
      reader._imageViewController = null;
    }
    super.dispose();
  }

  void onPositionChanged() {
    if (itemPositionsListener.itemPositions.value.isEmpty) {
      return;
    }
    var page = itemPositionsListener.itemPositions.value.first.index;
    page = page.clamp(1, reader.maxPage);
    if (page != reader.page) {
      reader.setPage(page);
      context.readerScaffold.update();
    }
    cacheImages(page);
  }

  double? _futurePosition;

  void smoothTo(double offset) {
    if (HardwareKeyboard.instance.isShiftPressed) {
      return;
    }
    var currentLocation = scrollController.position.pixels;
    var old = _futurePosition;
    _futurePosition ??= currentLocation;
    double k = (_futurePosition! - currentLocation).abs() / 1600 + 1;
    final customSpeed = appdata.settings.getReaderSetting(
      context.reader.cid,
      context.reader.type.sourceKey,
      "readerScrollSpeed",
    );
    if (customSpeed is num) {
      k *= customSpeed;
    }
    _futurePosition = _futurePosition! + offset * k;
    var beforeOffset = (_futurePosition! - currentLocation).abs();
    _futurePosition = _futurePosition!.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );
    var afterOffset = (_futurePosition! - currentLocation).abs();
    if (_futurePosition == old) return;
    var target = _futurePosition!;
    var duration = const Duration(milliseconds: 160);
    if (afterOffset < beforeOffset) {
      duration = duration * (afterOffset / beforeOffset);
      if (duration < Duration(milliseconds: 10)) {
        duration = Duration(milliseconds: 10);
      }
    }
    scrollController
        .animateTo(_futurePosition!, duration: duration, curve: Curves.linear)
        .then((_) {
          var current = scrollController.position.pixels;
          if (current == target && current == _futurePosition) {
            _futurePosition = null;
          }
        });
  }

  void onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (!_isMouseScrolling) {
        setState(() {
          _isMouseScrolling = true;
        });
      }
      if (isCTRLPressed) {
        return;
      }
      smoothTo(event.scrollDelta.dy);
    }
  }

  void cacheImages(int current) {
    for (int i = current + 1; i <= current + preCacheCount; i++) {
      if (i <= reader.maxPage && !cached[i]) {
        _preDownloadImage(i, context);
        cached[i] = true;
      }
    }
  }

  void onScroll() {
    if (prepareToPrevChapter) {
      jumpToNextChapter = false;
      jumpToPrevChapter =
          scrollController.offset <
          scrollController.position.minScrollExtent - _kChangeChapterOffset;
    } else if (prepareToNextChapter) {
      jumpToNextChapter =
          scrollController.offset >
          scrollController.position.maxScrollExtent + _kChangeChapterOffset;
      jumpToPrevChapter = false;
    }
  }

  bool onScaleUpdate([double? scale]) {
    if (prepareToNextChapter || prepareToPrevChapter) {
      setState(() {
        prepareToPrevChapter = false;
        prepareToNextChapter = false;
      });
      context.readerScaffold.setFloatingButton(0);
    }
    var isZoomedIn = (scale ?? photoViewController.scale) != 1.0;
    if (isZoomedIn != this.isZoomedIn) {
      setState(() {
        this.isZoomedIn = isZoomedIn;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    Widget widget = ScrollablePositionedList.builder(
      initialScrollIndex: reader.page,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      scrollControllerCallback: (scrollController) {
        if (_scrollController != null) {
          _scrollController!.removeListener(onScroll);
        }
        _scrollController = scrollController;
        _scrollController!.addListener(onScroll);
      },
      itemCount: reader.maxPage + 2,
      addSemanticIndexes: false,
      scrollDirection: reader.mode == ReaderMode.continuousTopToBottom
          ? Axis.vertical
          : Axis.horizontal,
      reverse: reader.mode == ReaderMode.continuousRightToLeft,
      physics: isCTRLPressed || _isMouseScrolling || disableScroll
          ? const NeverScrollableScrollPhysics()
          : isZoomedIn
          ? const ClampingScrollPhysics()
          : const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        if (index == 0 || index == reader.maxPage + 1) {
          return const SizedBox();
        }
        double? width, height;
        if (reader.mode == ReaderMode.continuousLeftToRight ||
            reader.mode == ReaderMode.continuousRightToLeft) {
          height = double.infinity;
        } else {
          width = double.infinity;
        }

        // ⭐ 2026-10-25：显式传"页面列表失效"回调 ✓（原先 ancestor 反查恒失效 ✗）。
        ImageProvider image = _createImageProvider(
          index,
          context,
          onLoadFailed: imagesState?._onPagesCacheInvalid,
        );

        return ColoredBox(
          color: readerImageBackgroundColor(
            context,
            comicId: reader.cid,
            sourceKey: reader.type.sourceKey,
          ),
          child: ComicImage(
            filterQuality: FilterQuality.medium,
            image: image,
            width: width,
            height: height,
            fit: BoxFit.contain,
            onInit: (state) => imageStates.add(state),
            onDispose: (state) => imageStates.remove(state),
          ),
        );
      },
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
        dragDevices: _kTouchLikeDeviceTypes,
      ),
    );

    widget = Stack(
      children: [
        Positioned.fill(child: buildBackground(context)),
        Positioned.fill(child: widget),
      ],
    );

    widget = Listener(
      onPointerDown: (event) {
        fingers++;
        if (fingers > 1 && !disableScroll) {
          setState(() {
            disableScroll = true;
          });
        }
        _futurePosition = null;
        if (_isMouseScrolling) {
          setState(() {
            _isMouseScrolling = false;
          });
        }
      },
      onPointerUp: (event) {
        fingers--;
        if (fingers <= 1 && disableScroll) {
          setState(() {
            disableScroll = false;
          });
        }
        if (fingers == 0) {
          if (jumpToPrevChapter) {
            context.readerScaffold.setFloatingButton(0);
            reader.toPrevChapter(toLastPage: true);
          } else if (jumpToNextChapter) {
            context.readerScaffold.setFloatingButton(0);
            reader.toNextChapter();
          }
        }
      },
      onPointerCancel: (event) {
        fingers--;
        if (fingers <= 1 && disableScroll) {
          setState(() {
            disableScroll = false;
          });
        }
      },
      onPointerPanZoomUpdate: (event) {
        if (event.scale == 1.0) {
          smoothTo(0 - event.panDelta.dy);
        }
      },
      onPointerMove: (event) {
        Offset value = event.delta;
        if (photoViewController.scale == 1 || fingers != 1) {
          return;
        }
        Offset offset;
        var sp = scrollController.position;
        if (sp.pixels <= sp.minScrollExtent ||
            sp.pixels >= sp.maxScrollExtent) {
          offset = Offset(value.dx, value.dy);
        } else {
          if (reader.mode == ReaderMode.continuousTopToBottom) {
            offset = Offset(value.dx, 0);
          } else {
            offset = Offset(0, value.dy);
          }
        }
        if (isLongPressing) {
          offset += value;
        }
        photoViewController.updateMultiple(
          position: photoViewController.position + offset,
        );
      },
      onPointerSignal: onPointerSignal,
      child: widget,
    );

    widget = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          delayedSetIsScrolling(true);
        } else if (notification is ScrollEndNotification) {
          delayedSetIsScrolling(false);
        }

        var scale = photoViewController.scale ?? 1.0;

        if (notification is ScrollUpdateNotification &&
            (scale - 1).abs() < 0.05) {
          if (!scrollController.hasClients) return false;
          if (scrollController.position.pixels <=
                  scrollController.position.minScrollExtent &&
              !reader.isFirstChapterOfGroup) {
            if (!prepareToPrevChapter) {
              jumpToPrevChapter = false;
              jumpToNextChapter = false;
              context.readerScaffold.setFloatingButton(-1);
              setState(() {
                prepareToPrevChapter = true;
              });
            }
          } else if (scrollController.position.pixels >=
                  scrollController.position.maxScrollExtent &&
              !reader.isLastChapterOfGroup) {
            if (!prepareToNextChapter) {
              jumpToPrevChapter = false;
              jumpToNextChapter = false;
              context.readerScaffold.setFloatingButton(1);
              setState(() {
                prepareToNextChapter = true;
              });
            }
          } else {
            context.readerScaffold.setFloatingButton(0);
            if (prepareToPrevChapter || prepareToNextChapter) {
              jumpToPrevChapter = false;
              jumpToNextChapter = false;
              setState(() {
                prepareToPrevChapter = false;
                prepareToNextChapter = false;
              });
            }
          }
        }

        return true;
      },
      child: widget,
    );
    var width = reader.size.width;
    var height = reader.size.height;
    if (appdata.settings.getReaderSetting(
              reader.cid,
              reader.type.sourceKey,
              'limitImageWidth',
            ) ==
            true &&
        width / height > 0.7 &&
        reader.mode == ReaderMode.continuousTopToBottom) {
      width = height * 0.7;
    }

    return PhotoView.customChild(
      backgroundDecoration: BoxDecoration(
        color: readerImageBackgroundColor(
          context,
          comicId: reader.cid,
          sourceKey: reader.type.sourceKey,
        ),
      ),
      childSize: Size(width, height),
      minScale: 1.0,
      maxScale: 2.5,
      strictScale: true,
      controller: photoViewController,
      onScaleUpdate: onScaleUpdate,
      child: SizedBox(width: width, height: height, child: widget),
    );
  }

  Widget buildBackground(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: context.padding.top + 16),
        if (prepareToPrevChapter)
          _SwipeChangeChapterProgress(
            controller: scrollController,
            isPrev: true,
          ),
        const Spacer(),
        if (prepareToNextChapter)
          _SwipeChangeChapterProgress(
            controller: scrollController,
            isPrev: false,
          ),
        SizedBox(height: 36),
      ],
    );
  }

  @override
  Future<void> animateToPage(int page) {
    return itemScrollController.scrollTo(
      index: page,
      duration: AppMotion.short,
      curve: Curves.ease,
    );
  }

  @override
  void handleDoubleTap(Offset location) {
    if (appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'quickCollectImage',
        ) ==
        'DoubleTap') {
      context.readerScaffold.addImageFavorite();
      return;
    }
    double target;
    if (photoViewController.scale !=
        photoViewController.getInitialScale?.call()) {
      target = photoViewController.getInitialScale!.call()!;
    } else {
      target = photoViewController.getInitialScale!.call()! * 1.75;
    }
    var size = MediaQuery.of(context).size;
    photoViewController.animateScale?.call(
      target,
      Offset(size.width / 2 - location.dx, size.height / 2 - location.dy),
    );
    onScaleUpdate(target);
  }

  @override
  void handleLongPressDown(Offset location) {
    if (!appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'enableLongPressToZoom',
        ) ||
        delayedIsScrolling) {
      return;
    }
    double target = photoViewController.getInitialScale!.call()! * 1.75;
    var size = reader.size;
    Offset zoomPosition;
    if (appdata.settings.getReaderSetting(
          reader.cid,
          reader.type.sourceKey,
          'longPressZoomPosition',
        ) !=
        'center') {
      zoomPosition = Offset(
        size.width / 2 - location.dx,
        size.height / 2 - location.dy,
      );
    } else {
      zoomPosition = Offset(0, 0);
    }
    photoViewController.animateScale?.call(target, zoomPosition);
    onScaleUpdate(target);
    isLongPressing = true;
  }

  @override
  void handleLongPressUp(Offset location) {
    if (!appdata.settings.getReaderSetting(
      reader.cid,
      reader.type.sourceKey,
      'enableLongPressToZoom',
    )) {
      return;
    }
    double target = photoViewController.getInitialScale!.call()!;
    photoViewController.animateScale?.call(target);
    onScaleUpdate(target);
    isLongPressing = false;
  }

  @override
  void toPage(int page) {
    itemScrollController.jumpTo(index: page);
    _futurePosition = null;
  }

  @override
  void handleKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight) {
      setState(() {
        if (event is KeyDownEvent) {
          isCTRLPressed = true;
        } else if (event is KeyUpEvent) {
          isCTRLPressed = false;
        }
      });
    }
    if (event is KeyUpEvent) {
      return;
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      smoothTo(context.height * 0.8);
      return;
    }
    bool? forward;
    if (reader.mode == ReaderMode.continuousLeftToRight &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      forward = true;
    } else if (reader.mode == ReaderMode.continuousRightToLeft &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      forward = true;
    } else if (reader.mode == ReaderMode.continuousTopToBottom &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      forward = true;
    } else if (reader.mode == ReaderMode.continuousTopToBottom &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      forward = false;
    } else if (reader.mode == ReaderMode.continuousLeftToRight &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      forward = false;
    } else if (reader.mode == ReaderMode.continuousRightToLeft &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      forward = false;
    }
    if (forward == true) {
      scrollController.animateTo(
        scrollController.offset + context.height * 0.25,
        duration: AppMotion.short,
        curve: Curves.ease,
      );
    } else if (forward == false) {
      scrollController.animateTo(
        scrollController.offset - context.height * 0.25,
        duration: AppMotion.short,
        curve: Curves.ease,
      );
    }
  }

  @override
  bool handleOnTap(Offset location) {
    if (delayedIsScrolling) {
      return true;
    }
    return false;
  }

  @override
  Future<Uint8List?> getImageByOffset(Offset offset) async {
    var imageKey = getImageKeyByOffset(offset);
    if (imageKey == null) return null;
    if (imageKey.startsWith("file://")) {
      return await File(imageKey.substring(7)).readAsBytes();
    } else {
      // ⭐ 修复（2026-10-09）：**去掉硬 `!` 强解包** —— 缓存被清理/过期时 findCache 返回 null，
      // 原写法会空指针崩溃。现改为显式抛错，交由 ImageProvider 的失败路径处理（显示失败/按需重试）；
      // **正常命中缓存的路径行为完全不变**（同一 key、同一 readAsBytes）。
      // ⭐ 修复（2026-10-25，P1）：键改走 `_smbPageCacheKey` ✓ —— 原先用 `type.sourceKey`
      // 拼键 ✗，对 SMB 会得到 `@smb@` 而真实键是 `@null@` ⇒ 收藏/保存恒报 cache missing ✓。
      final cached = await CacheManager().findCache(
        _smbPageCacheKey(reader, imageKey),
      );
      if (cached == null || !cached.existsSync()) {
        throw Exception("Reader image cache missing: $imageKey");
      }
      return cached.readAsBytes();
    }
  }

  @override
  String? getImageKeyByOffset(Offset offset) {
    String? imageKey;
    for (var imageState in imageStates) {
      if ((imageState as _ComicImageState).containsPoint(offset)) {
        imageKey = (imageState.widget.image as ReaderImageProvider).imageKey;
      }
    }
    return imageKey;
  }
}

ImageProvider _createImageProviderFromKey(
  String imageKey,
  BuildContext context,
  int page, {
  bool forPrefetch = false,

  /// ⭐ 修复（2026-10-25，P2）：**显式传入"页面列表失效"回调** ✗→✓ ——
  /// 原先在这里用 `context.visitAncestorElements` 反查 `_ReaderImagesState` ✗：
  /// `visitAncestorElements` 是从**当前元素往上**遍历 ✓，而对每个祖先再调
  /// `findAncestorStateOfType` 只会找到**该祖先的更上层** ✓ ⇒ 在 builder 的 context 里
  /// `imagesState` **恒为 null** ✗ ⇒ `onLoadFailed` 恒失效 ✓（图片加载失败不再触发整章重载 ✓）。
  /// 现在由调用方（`_GalleryModeState` / `_ContinuousModeState` 在 initState 里取一次 ✓）显式传入 ✓。
  VoidCallback? onLoadFailed,
}) {
  var reader = context.reader;
  return ReaderImageProvider(
    imageKey,
    reader.type.comicSource?.key,
    reader.cid,
    reader.eid,
    reader.page,
    // ⭐ 修复（2026-10-24）：SMB 页同样启用解码降采样。
    // 原因：几百页长章节里每页都按原分辨率解码，是 OOM 闪退的主因之一；
    // 降采样只在像素数超过上限（且宽高比正常）的图上生效，不影响小图清晰度。
    enableResize: reader.mode.isContinuous || imageKey.startsWith('smb://'),
    // ⭐ 复查修复（2026-10-24）：预解码用**低优先级** ✓ ——
    // 否则相邻页预解码会去抢前台名额 ⇒ 当前页反而被判 "SMB read busy." ✗。
    lowPriority: forPrefetch,
    // ⭐ 2026-10-24：**SMB 页不接"页面列表失效"回调** ✗ ——
    // 该回调会把 `reader.isLoading` 置 true ⇒ **整个阅读器弹大圈重载页面列表** ✗
    // （用户实测症状：待一会后 / 连翻两页时"闪一下大圈转半秒再回到画面" ✓）。
    // SMB 单页读取失败多是瞬时问题（NAS 忙、请求被更新的页顶掉 ✓）⇒ 交给该页自己的
    // 错误+重试界面即可 ✓，不该连累整章 ✓。
    // ⭐ 复查修复（2026-10-24）：**预取/预解码也不接** ✓ ——
    // `precacheImage` 的 `onError` 只能吃掉"未来" ✓，挡不住 provider 内部 `onLoadError()` ✗
    // ⇒ 后台预取失败会把整章重载 ✗（用户看到"停一会后转大圈"✓）。
    onLoadFailed: (forPrefetch || imageKey.startsWith('smb://'))
        ? null
        : onLoadFailed,
  );
}

ImageProvider _createImageProvider(
  int page,
  BuildContext context, {
  bool forPrefetch = false,

  /// 透传"页面列表失效"回调 ✓（见 `_createImageProviderFromKey` 注释 ✓）。
  VoidCallback? onLoadFailed,
}) {
  var reader = context.reader;
  var imageKey = reader.images![page - 1];
  return _createImageProviderFromKey(
    imageKey,
    context,
    page,
    forPrefetch: forPrefetch,
    onLoadFailed: onLoadFailed,
  );
}

/// [_precacheImage] is used to precache the image for the given page.
/// The image is cached using the flutter's [precacheImage] method.
/// The image will be downloaded and decoded into memory.
void _precacheImage(int page, BuildContext context) {
  if (page <= 0 || page > context.reader.images!.length) {
    return;
  }
  // ⭐ 2026-10-24：预解码**低优先级 + 不接整页重载回调** ✓（见 `_createImageProviderFromKey` 注释 ✓）。
  // ⚠️ 复查纠正：`precacheImage` 的 `onError` **挡不住** provider 内部的 `onLoadError()` ✗
  //（后者在 `base_image_provider.dart` 里独立调用 ✓）⇒ 必须从 provider 侧（`onLoadFailed: null`）解决 ✓。
  precacheImage(
    _createImageProvider(page, context, forPrefetch: true),
    context,
    onError: (_, _) {},
  );
}

/// [_preDownloadImage] is used to download the image for the given page.
/// The image is downloaded using the [CacheManager] and saved to the local storage.
void _preDownloadImage(int page, BuildContext context) {
  if (page <= 0 || page > context.reader.images!.length) {
    return;
  }
  var reader = context.reader;
  var imageKey = reader.images![page - 1];
  var cid = reader.cid;
  var eid = reader.eid;
  var sourceKey = reader.type.comicSource?.key;
  // file:// 就是本机磁盘上的文件，本来就在盘上 ⇒ 无需预取。
  if (imageKey.startsWith("file://")) {
    return;
  }
  // ⭐ 修复（2026-10-24）：SMB 页改为「落盘预取」（只读字节写盘，**不解码**）。
  // 原先一律跳过 SMB ⇒ 预加载数量对 NAS 完全失效，翻页只能现读现解码（闪烁且无缓冲）。
  // 现在由 ReaderImageProvider.prefetchSmbPage 后台读并写入磁盘缓存，
  // 并发上限由那边的信号量兜住；预取失败静默，不影响阅读。
  if (imageKey.startsWith("smb://")) {
    ReaderImageProvider.prefetchSmbPage(imageKey, sourceKey, cid, eid);
    return;
  }
  ImageDownloader.loadComicImage(imageKey, sourceKey, cid, eid);
}

class _SwipeChangeChapterProgress extends StatefulWidget {
  const _SwipeChangeChapterProgress({this.controller, required this.isPrev});

  final ScrollController? controller;

  final bool isPrev;

  @override
  State<_SwipeChangeChapterProgress> createState() =>
      _SwipeChangeChapterProgressState();
}

class _SwipeChangeChapterProgressState
    extends State<_SwipeChangeChapterProgress> {
  double value = 0;

  late final isPrev = widget.isPrev;

  ScrollController? controller;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      controller = widget.controller;
      controller!.addListener(onScroll);
    }
  }

  @override
  void didUpdateWidget(covariant _SwipeChangeChapterProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      controller?.removeListener(onScroll);
      controller = widget.controller;
      controller?.addListener(onScroll);
      if (value != 0) {
        setState(() {
          value = 0;
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
    controller?.removeListener(onScroll);
  }

  void onScroll() {
    var position = controller!.position.pixels;
    var offset = isPrev
        ? controller!.position.minScrollExtent - position
        : position - controller!.position.maxScrollExtent;
    var newValue = offset / _kChangeChapterOffset;
    newValue = newValue.clamp(0.0, 1.0);
    if (newValue != value) {
      setState(() {
        value = newValue;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.isPrev
        ? "Swipe down for previous chapter".tl
        : "Swipe up for next chapter".tl;

    return CustomPaint(
      painter: _ProgressPainter(
        value: value,
        backgroundColor: context.colorScheme.surfaceContainerLow,
        color: context.colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.isPrev ? Icons.arrow_downward : Icons.arrow_upward,
            // ⭐ 图标取色（2026-10-11）：显式色会压掉外层注入 ✗ ⇒ 经用户层再给 ✓
            //（用户设了「图标颜色」优先 ✓，否则仍用原来的 `onSurface` ✓）。
            color: appIconColor(context, context.colorScheme.onSurface),
            size: AppIconSize.xs,
          ),
          const SizedBox(width: 4),
          Text(msg),
        ],
      ).paddingVertical(6).paddingHorizontal(16),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double value;

  final Color backgroundColor;

  final Color color;

  const _ProgressPainter({
    required this.value,
    required this.backgroundColor,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        0,
        size.width,
        size.height,
        Radius.circular(AppRadius.xl),
      ),
      paint,
    );

    paint.color = color;
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        0,
        size.width * value,
        size.height,
        Radius.circular(AppRadius.xl),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _ProgressPainter ||
        oldDelegate.value != value ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.color != color;
  }
}
