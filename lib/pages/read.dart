import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:synchronized/synchronized.dart';
import 'package:tuple/tuple.dart';
import 'package:mikack/models.dart' as models;
import '../widgets/text_hint.dart';
import '../widgets/outline_text.dart';

const backgroundColor = Color.fromARGB(255, 50, 50, 50);
const pageInfoTextColor = Color.fromARGB(255, 255, 255, 255);
const pageInfoOutlineColor = Color.fromARGB(255, 0, 0, 0);
const pageInfoFontSize = 10.0;
const spinkitSize = 35.0;
const connectionIndicatorColor = Color.fromARGB(255, 138, 138, 138);

class PagesView extends StatelessWidget {
  PagesView(this.chapter, this.addresses, this.currentPage, this.handleNext,
      this.handlePrev,
      {this.scrollController, this.waiting = false});

  final models.Chapter chapter;
  final List<String> addresses;
  final int currentPage;
  final void Function(int) handleNext;
  final void Function(int) handlePrev;
  final ScrollController scrollController;
  final bool waiting;

  bool isLoading() {
    return (addresses == null || addresses.length == 0 || waiting);
  }

  Widget _buildLoadingView() {
    if (waiting) {
      return SpinKitPouringHourglass(
          color: connectionIndicatorColor, size: spinkitSize);
    } else {
      return const TextHint('载入中…');
    }
  }

  final connectingIndicator = SpinKitWave(
    color: connectionIndicatorColor,
    size: spinkitSize,
  );

  Widget _buildImageView() {
    return Image.network(
      addresses[currentPage - 1],
      headers: chapter.pageHeaders,
      loadingBuilder: (BuildContext context, Widget child,
          ImageChunkEvent loadingProgress) {
        if (loadingProgress == null) {
          if (child is Semantics) {
            var rawImage = child.child;
            if (rawImage is RawImage) {
              if (rawImage.image == null)
                return Center(
                  child: connectingIndicator,
                );
            }
          }
          return child;
        }
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes
                : null,
          ),
        );
      },
    );
  }

  Widget _buildView() {
    return isLoading()
        ? _buildLoadingView()
        : ListView(
            shrinkWrap: true,
            children: [_buildImageView()],
            controller: scrollController,
          );
  }

  void _handleTapUp(TapUpDetails details, BuildContext context) {
    if (isLoading()) return;
    var centerLocation = MediaQuery.of(context).size.width / 2;
    var x = details.globalPosition.dx;

    if (centerLocation > x) {
      handlePrev(currentPage);
    } else {
      handleNext(currentPage);
    }
  }

  // 构建页码信息视图
  Widget _buildPageInfoView() {
    var pageInfo = chapter == null ? '' : '$currentPage/${chapter.pageCount}';
    return Positioned(
      bottom: 2,
      left: 0,
      right: 0,
      child: Container(
        child: Center(
          child: OutlineText(
            pageInfo,
            fontSize: pageInfoFontSize,
            textColor: pageInfoTextColor,
            outlineColor: pageInfoOutlineColor,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(
          children: [
            Positioned.fill(
                child: Container(child: Center(child: _buildView()))),
            _buildPageInfoView(),
          ],
        ),
      ),
      onTapUp: (detail) => _handleTapUp(detail, context),
    );
  }
}

class _MainView extends StatefulWidget {
  _MainView(this.platform, this.chapter);

  final models.Platform platform;
  final models.Chapter chapter;

  @override
  State<StatefulWidget> createState() => _MainViewState();
}

class _MainViewState extends State<_MainView> {
  var _currentPage = 0;
  var _addresses = <String>[];
  bool _waiting = false;
  models.Chapter _chapter;
  models.PageIterator _pageInterator;

  final ScrollController pageScrollController = ScrollController();

  @override
  void initState() {
    // 创建页面迭代器
    createPageInterator(context);
    super.initState();
  }

  @override
  void dispose() {
    if (_pageInterator != null) _pageInterator.free();
    super.dispose();
  }

  void createPageInterator(BuildContext context) async {
    var created = await compute(
        _createPageIteratorTask, Tuple2(widget.platform, widget.chapter));
    setState(() {
      _pageInterator = created.item1.asPageIterator();
      _chapter = created.item2;
    });
    // 加载第一页
    fetchNextPage(turning: true);
  }

  final lock = Lock();

  void fetchNextPage({turning = false, preCount = 2}) async {
    // 同步资源下载和地址池写入
    if (turning) setState(() => _waiting = true);
    await lock.synchronized(() async {
      if (_addresses.length >= _chapter.pageCount) return;
      var address = await compute(
          _getNextAddressTask, _pageInterator.asValuePageInaterator());
      setState(() {
        _addresses.add(address);
        if (turning) {
          _waiting = false;
          _currentPage++;
        }
      });
      // 预缓存（立即翻页的不缓存）
      if (!turning)
        precacheImage(
            NetworkImage(address, headers: _chapter.pageHeaders), context);
    });
    // 预下载
    if (preCount > 0) fetchNextPage(preCount: --preCount);
  }

  void handleNext(page) {
    var currentCount = _addresses.length;
    if (page == _chapter.pageCount) return;
    // 直接修改页码
    if (page < currentCount) {
      setState(() {
        _currentPage = page + 1;
      });
      // 预下载
      if ((page + 1) == currentCount) fetchNextPage();
    } else {
      fetchNextPage(turning: true, preCount: 0); // 加载并翻页
    }
    pageScrollController.jumpTo(0);
  }

  void handlePrev(page) {
    var currentCount = _addresses.length;
    if (page <= 1 || page > currentCount) return;
    // 直接修改页码
    if (page <= currentCount) {
      setState(() {
        _currentPage = page - 1;
      });
    }
    pageScrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return PagesView(_chapter, _addresses, _currentPage, handleNext, handlePrev,
        scrollController: pageScrollController, waiting: _waiting);
  }
}

class ReadPage extends StatelessWidget {
  ReadPage(this.platform, this.chapter);

  final models.Platform platform;
  final models.Chapter chapter;

  @override
  Widget build(BuildContext context) {
    return _MainView(platform, chapter);
  }
}

class ValuePageIterator {
  int createdIterPointerAddress;
  int iterPointerAddress;

  ValuePageIterator(this.createdIterPointerAddress, this.iterPointerAddress);

  models.PageIterator asPageIterator() {
    return models.PageIterator(
        Pointer.fromAddress(this.createdIterPointerAddress),
        Pointer.fromAddress(this.iterPointerAddress));
  }
}

extension PageInteratorCopyable on models.PageIterator {
  ValuePageIterator asValuePageInaterator() {
    return ValuePageIterator(
        this.createdIterPointer.address, this.iterPointer.address);
  }
}

String _getNextAddressTask(ValuePageIterator valuePageIterator) {
  return valuePageIterator.asPageIterator().next();
}

Tuple2<ValuePageIterator, models.Chapter> _createPageIteratorTask(
    Tuple2<models.Platform, models.Chapter> args) {
  var platform = args.item1;
  var chapter = args.item2;

  var pageIterator = platform.createPageIter(chapter);

  return Tuple2(
    ValuePageIterator(
      pageIterator.createdIterPointer.address,
      pageIterator.iterPointer.address,
    ),
    chapter,
  );
}
