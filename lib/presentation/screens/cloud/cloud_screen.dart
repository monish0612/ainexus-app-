import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/platform/io_stub.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/services/transfer_notification.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/google_drive_service.dart';
import '../../../data/services/nas_files_service.dart';
import '../../../domain/entities/nas_file.dart';
import '../../providers/cloud_destination_provider.dart';
import '../../widgets/compact_header.dart';
import '../settings/settings_modal.dart';
import 'stats/widgets/stats_launcher.dart';
import 'widgets/destination_switch.dart';

// ── UI Models ────────────────────────────────────────────────────────────────

enum CloudFileKind { pdf, image, document, video, other }

enum HistoryActionKind { upload, download, delete, sync }

@immutable
class CloudFileItem {
  const CloudFileItem({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.ext,
    required this.dateLabel,
    required this.starred,
    required this.kind,
    this.thumbnailLink,
    this.isImage = false,
  });

  factory CloudFileItem.fromDriveInfo(DriveFileInfo info) {
    final ext = info.ext;
    return CloudFileItem(
      id: info.id,
      name: info.name,
      sizeBytes: info.size,
      ext: ext,
      dateLabel: _formatDateLabel(info.modifiedTime),
      starred: info.starred,
      kind: _kindFromExt(ext),
      thumbnailLink: info.thumbnailLink,
      isImage: info.isImage,
    );
  }

  /// A file on the NAS, in the shape the file list already understands.
  ///
  /// The id is the name, because on a WebDAV share that is genuinely what
  /// identifies a file — there is no opaque handle to carry around. It also
  /// means a file renamed on the share from a laptop is a different file to
  /// this list, which is the truth rather than a bug.
  ///
  /// `starred` is always false: the NAS has nowhere to record a star, and a
  /// star that silently forgot itself on the next refresh would be worse than
  /// no star at all. The UI hides the control for NAS files rather than
  /// offering one that does nothing.
  factory CloudFileItem.fromNasFile(NasFile info) {
    final ext = info.ext;
    return CloudFileItem(
      id: info.name,
      name: info.name,
      sizeBytes: info.sizeBytes,
      ext: ext,
      // A NAS listing can omit the timestamp; say so rather than dating the
      // file to now, which would sort and read as a fresh upload.
      dateLabel: info.modified == null
          ? 'Date unknown'
          : _formatDateLabel(info.modified!),
      starred: false,
      kind: _kindFromExt(ext),
      isImage: const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'}
          .contains(ext),
    );
  }

  final String id;
  final String name;
  final int sizeBytes;
  final String ext;
  final String dateLabel;
  final bool starred;
  final CloudFileKind kind;
  final String? thumbnailLink;
  final bool isImage;

  CloudFileItem copyWith({bool? starred, String? dateLabel}) {
    return CloudFileItem(
      id: id,
      name: name,
      sizeBytes: sizeBytes,
      ext: ext,
      dateLabel: dateLabel ?? this.dateLabel,
      starred: starred ?? this.starred,
      kind: kind,
      thumbnailLink: thumbnailLink,
      isImage: isImage,
    );
  }
}

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    required this.fileName,
  });

  final String id;
  final DateTime at;
  final HistoryActionKind kind;
  final String title;
  final String fileName;
}

enum FileFilter { all, documents, images, videos, starred }

// ── Formatters ───────────────────────────────────────────────────────────────

String _fmtBytes(int b) {
  if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '$b B';
}

String _fmtEta(double seconds) {
  if (seconds <= 0 || !seconds.isFinite) return '00:00';
  final m = seconds ~/ 60;
  final s = (seconds % 60).floor();
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _formatDateLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';
  if (diff < 14) return '1 week ago';
  return DateFormat.yMMMd().format(d);
}

IconData _iconForKind(CloudFileKind kind) {
  switch (kind) {
    case CloudFileKind.pdf:
      return LucideIcons.fileText;
    case CloudFileKind.image:
      return LucideIcons.image;
    case CloudFileKind.document:
      return LucideIcons.fileText;
    case CloudFileKind.video:
      return LucideIcons.film;
    case CloudFileKind.other:
      return LucideIcons.file;
  }
}

Color _iconColorForKind(CloudFileKind kind, AppColors colors) {
  switch (kind) {
    case CloudFileKind.pdf:
      return const Color(0xFFEF4444);
    case CloudFileKind.image:
      return const Color(0xFF34D399);
    case CloudFileKind.document:
      return const Color(0xFF60A5FA);
    case CloudFileKind.video:
      return const Color(0xFF818CF8);
    case CloudFileKind.other:
      return colors.text3;
  }
}

CloudFileKind _kindFromExt(String ext) {
  final e = ext.toLowerCase();
  if (e == 'pdf') return CloudFileKind.pdf;
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(e)) {
    return CloudFileKind.image;
  }
  if (['mp4', 'mov', 'mkv', 'webm'].contains(e)) return CloudFileKind.video;
  if (['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md']
      .contains(e)) {
    return CloudFileKind.document;
  }
  return CloudFileKind.other;
}

Color _historyAccent(HistoryActionKind k) {
  switch (k) {
    case HistoryActionKind.upload:
      return AppColors.accent;
    case HistoryActionKind.download:
      return const Color(0xFF34D399);
    case HistoryActionKind.delete:
      return const Color(0xFFF87171);
    case HistoryActionKind.sync:
      return const Color(0xFFCC5DE8);
  }
}

IconData _historyIcon(HistoryActionKind k) {
  switch (k) {
    case HistoryActionKind.upload:
      return LucideIcons.uploadCloud;
    case HistoryActionKind.download:
      return LucideIcons.download;
    case HistoryActionKind.delete:
      return LucideIcons.trash2;
    case HistoryActionKind.sync:
      return LucideIcons.refreshCw;
  }
}

bool _matchesFilter(CloudFileItem f, FileFilter filter) {
  switch (filter) {
    case FileFilter.all:
      return true;
    case FileFilter.documents:
      return f.kind == CloudFileKind.pdf || f.kind == CloudFileKind.document;
    case FileFilter.images:
      return f.kind == CloudFileKind.image;
    case FileFilter.videos:
      return f.kind == CloudFileKind.video;
    case FileFilter.starred:
      return f.starred;
  }
}

String _groupLabelForDate(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat.yMMMd().format(d);
}

// ── Dashed border painter ────────────────────────────────────────────────────

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;
  static const double _strokeWidth = 1.5;
  static const double _dash = 7;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          _strokeWidth / 2, _strokeWidth / 2,
          size.width - _strokeWidth, size.height - _strokeWidth),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + _dash, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Storage ring ─────────────────────────────────────────────────────────────

class _StorageRingPainter extends CustomPainter {
  _StorageRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });
  final double progress;
  final Color trackColor;
  final Color progressColor;
  static const double _strokeWidth = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.shortestSide - _strokeWidth) / 2;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final prog = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, track);
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), -math.pi / 2, sweep, false, prog);
  }

  @override
  bool shouldRepaint(covariant _StorageRingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}

// ── Screen ───────────────────────────────────────────────────────────────────

class CloudScreen extends ConsumerStatefulWidget {
  const CloudScreen({super.key});

  @override
  ConsumerState<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends ConsumerState<CloudScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<CloudFileItem> _files = [];
  final List<HistoryEntry> _history = [];
  FileFilter _filter = FileFilter.all;
  bool _loading = true;
  String? _error;
  String? _errorDetail;
  String _errorTitle = 'Connection Failed';
  IconData _errorIcon = LucideIcons.cloudOff;

  double _usedGb = 0;
  double _totalGb = 15;

  // Pagination
  String? _nextPageToken;
  bool _loadingMore = false;

  // Search
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  Timer? _searchDebounce;

  // Active transfer state (survives sheet dismiss)
  CancelToken? _activeCancelToken;
  ValueNotifier<_TransferProgress>? _activeProgressNotifier;
  bool _transferSheetOpen = false;
  bool _isUploading = false; // true = upload, false = download

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _activeCancelToken?.cancel('Screen disposed');
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _searchQuery = query.trim());
      if (query.trim().isEmpty) {
        _loadFiles();
      } else {
        _performSearch(query.trim());
      }
    });
  }

  Future<void> _performSearch(String query) async {
    // The NAS folder is already fully in memory — a PROPFIND returns all of it
    // — so searching it is a filter, not a round trip. The filter is applied at
    // render time from `_searchQuery`; there is nothing to fetch.
    if (_destination == CloudDestination.nas) {
      setState(() => _isSearching = false);
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final driveService = ref.read(googleDriveServiceProvider);
      final result = await driveService.searchFiles(query);

      if (!mounted) return;
      setState(() {
        _files = result.files.map((f) => CloudFileItem.fromDriveInfo(f)).toList();
        _nextPageToken = result.nextPageToken;
        _isSearching = false;
      });
    } catch (e) {
      TLog.e('Cloud', 'Search failed', error: e);
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _applyDriveError(e);
      });
    }
  }

  /// Translate a raw Drive failure into an accurate title/message/detail so the
  /// error view explains the real cause instead of always blaming the network.
  void _applyDriveError(Object e) {
    final de = GoogleDriveService.classifyError(e);
    _error = de.message;
    _errorDetail = de.detail;
    switch (de.kind) {
      case DriveErrorKind.notConfigured:
        _errorTitle = 'Cloud Not Set Up';
        _errorIcon = LucideIcons.settings;
      case DriveErrorKind.auth:
        _errorTitle = 'Authentication Failed';
        _errorIcon = LucideIcons.lock;
      case DriveErrorKind.network:
        _errorTitle = 'Connection Failed';
        _errorIcon = LucideIcons.cloudOff;
      case DriveErrorKind.unknown:
        _errorTitle = 'Something Went Wrong';
        _errorIcon = LucideIcons.alertTriangle;
    }
  }

  /// Where this screen is currently pointed. Read rather than watched in the
  /// async paths so a switch mid-flight cannot make a reply land in the wrong
  /// list — each load captures the destination it was started for and drops its
  /// result if that is no longer the destination on screen.
  CloudDestination get _destination => ref.read(cloudDestinationProvider);

  Future<void> _loadFiles() async {
    if (_destination == CloudDestination.nas) return _loadNasFiles();
    return _loadDriveFiles();
  }

  /// Everything in the NAS `Cloud Storage` folder.
  ///
  /// No pagination and no server-side search: a WebDAV PROPFIND returns the
  /// folder in one reply, and this folder holds what a phone has put in it, not
  /// a Drive-sized archive. Paginating it would be machinery with nothing to do.
  Future<void> _loadNasFiles() async {
    setState(() {
      _loading = true;
      _error = null;
      _nextPageToken = null;
    });

    // Refreshing the list is also the cheapest moment to re-check whether the
    // NAS came back, which keeps the switch honest without a second poll.
    unawaited(ref.read(nasAvailabilityProvider.notifier).refresh());

    try {
      final files = await ref.read(nasFilesServiceProvider).listFiles();
      if (!mounted || _destination != CloudDestination.nas) return;
      setState(() {
        _files = files.map(CloudFileItem.fromNasFile).toList();
        _loading = false;
        _addHistory(HistoryActionKind.sync, 'Synced with NAS',
            '${files.length} file${files.length == 1 ? '' : 's'} loaded');
      });
    } on NasUnavailable catch (e) {
      if (!mounted || _destination != CloudDestination.nas) return;
      setState(() {
        _loading = false;
        _files = [];
        _error = e.message;
        _errorDetail = e.isNotConfigured
            ? 'Set NAS_WEBDAV_PASSWORD on the server to a Nextcloud app '
                'password. Google Drive is unaffected.'
            : 'Switch the NAS on and pull down to refresh. You can also '
                'switch back to Google Drive above.';
        _errorTitle =
            e.isNotConfigured ? 'NAS Not Set Up' : 'NAS Not Reachable';
        _errorIcon =
            e.isNotConfigured ? LucideIcons.lock : LucideIcons.powerOff;
      });
    } catch (e) {
      TLog.e('Cloud/NAS', 'Load NAS files failed', error: e);
      if (!mounted || _destination != CloudDestination.nas) return;
      setState(() {
        _loading = false;
        _files = [];
        _error = 'Could not read the NAS folder.';
        _errorDetail = null;
        _errorTitle = 'Something Went Wrong';
        _errorIcon = LucideIcons.alertTriangle;
      });
    }
  }

  Future<void> _loadDriveFiles() async {
    setState(() {
      _loading = true;
      _error = null;
      _nextPageToken = null;
    });

    try {
      final driveService = ref.read(googleDriveServiceProvider);
      final results = await Future.wait([
        driveService.listFiles(pageSize: 50),
        driveService.getStorageQuota(),
      ]);

      final fileResult = results[0] as DriveFileListResult;
      final quota = results[1] as DriveStorageQuota;

      if (!mounted || _destination != CloudDestination.drive) return;
      setState(() {
        _files = fileResult.files
            .map((f) => CloudFileItem.fromDriveInfo(f))
            .toList();
        _nextPageToken = fileResult.nextPageToken;
        _usedGb = quota.usedGb;
        _totalGb = quota.totalGb > 0 ? quota.totalGb : 15;
        _loading = false;
        _addHistory(HistoryActionKind.sync, 'Synced with Google Drive',
            '${fileResult.files.length} files loaded');
      });
    } catch (e) {
      TLog.e('Cloud', 'Load files failed', error: e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _applyDriveError(e);
      });
    }
  }

  Future<void> _loadMoreFiles() async {
    if (_loadingMore || _nextPageToken == null) return;
    setState(() => _loadingMore = true);

    try {
      final driveService = ref.read(googleDriveServiceProvider);
      final result = await driveService.listFiles(
        pageToken: _nextPageToken,
        pageSize: 50,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

      if (!mounted) return;
      setState(() {
        _files.addAll(
          result.files.map((f) => CloudFileItem.fromDriveInfo(f)),
        );
        _nextPageToken = result.nextPageToken;
        _loadingMore = false;
      });
    } catch (e) {
      TLog.w('Cloud', 'Load more files failed: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _addHistory(HistoryActionKind kind, String title, String fileName) {
    _history.insert(
      0,
      HistoryEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        at: DateTime.now(),
        kind: kind,
        title: title,
        fileName: fileName,
      ),
    );
  }

  Future<void> _openUploadFlow() async {
    final destination = _destination;

    if (!PlatformCapabilities.canUseGoogleDrive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Uploading is coming soon on the web. Use the Android app for now.',
          ),
        ),
      );
      return;
    }
    if (_hasActiveTransfer) {
      _showTransferBusySnack();
      return;
    }

    // Refuse before the file picker rather than after, so he is not asked to
    // choose a file that has nowhere to go.
    if (destination == CloudDestination.nas) {
      final nas = ref.read(nasAvailabilityProvider);
      if (!nas.isReady && nas.state != NasStorageState.unknown) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(
              'Cannot upload to the NAS: ${nas.explanation.toLowerCase()}',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
          ));
        return;
      }
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty || !mounted) return;

    final validPicks =
        result.files.where((f) => f.path != null).toList();
    if (validPicks.isEmpty) return;

    final totalBytes =
        validPicks.fold<int>(0, (sum, f) => sum + f.size);

    // The 10 GB ceiling is Google's, so it is only enforced for Google. The NAS
    // is bounded by the free space in its own pool, and the server answers 507
    // with a real explanation when that runs out — a better answer than an
    // invented app-side limit that would be wrong the moment a disk is added.
    if (destination == CloudDestination.drive) {
      if (totalBytes > GoogleDriveService.maxUploadBytes) {
        _showSizeExceededError(totalBytes, validPicks.length);
        return;
      }

      for (final picked in validPicks) {
        if (picked.size > GoogleDriveService.maxUploadBytes) {
          _showSizeExceededError(picked.size, 1, fileName: picked.name);
          return;
        }
      }
    }

    if (validPicks.length == 1) {
      final pickedFile = validPicks.first;
      final file = File(pickedFile.path!);
      final ext = pickedFile.extension ?? '';
      final tempItem = CloudFileItem(
        id: 'uploading_${DateTime.now().millisecondsSinceEpoch}',
        name: pickedFile.name,
        sizeBytes: pickedFile.size,
        ext: ext,
        dateLabel: 'Uploading…',
        starred: false,
        kind: _kindFromExt(ext),
      );

      setState(() => _files.insert(0, tempItem));

      _showTransferSheet(
        file: tempItem,
        isUpload: true,
        realFile: file,
      );
      return;
    }

    // Multi-file upload
    final pairs = <(CloudFileItem, File)>[];
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < validPicks.length; i++) {
      final picked = validPicks[i];
      final ext = picked.extension ?? '';
      final tempItem = CloudFileItem(
        id: 'uploading_${ts}_$i',
        name: picked.name,
        sizeBytes: picked.size,
        ext: ext,
        dateLabel: 'Queued…',
        starred: false,
        kind: _kindFromExt(ext),
      );
      pairs.add((tempItem, File(picked.path!)));
    }

    setState(() {
      for (final (item, _) in pairs) {
        _files.insert(0, item);
      }
    });

    TLog.i('Cloud', 'Multi-upload started: ${pairs.length} files, '
        '${_fmtBytes(totalBytes)} total');

    _showMultiTransferSheet(pairs, totalBytes);
  }

  void _showSizeExceededError(int bytes, int fileCount, {String? fileName}) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final label = fileName ?? '$fileCount file${fileCount > 1 ? 's' : ''}';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bg1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
        title: Row(children: [
          const Icon(LucideIcons.alertTriangle,
              color: Color(0xFFF87171), size: 22),
          const SizedBox(width: 10),
          Text('File Too Large',
              style: GoogleFonts.plusJakartaSans(
                  color: colors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          '$label (${_fmtBytes(bytes)}) exceeds the 10 GB limit.',
          style: GoogleFonts.plusJakartaSans(
              color: colors.text2, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK',
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showTransferSheet({
    required CloudFileItem file,
    required bool isUpload,
    File? realFile,
  }) {
    _activeCancelToken = CancelToken();
    _isUploading = isUpload;

    final progressNotifier = ValueNotifier<_TransferProgress>(
      _TransferProgress(fraction: 0, transferred: 0, total: file.sizeBytes),
    );
    _activeProgressNotifier = progressNotifier;

    if (isUpload && realFile != null) {
      _doUpload(realFile, file, progressNotifier);
    } else if (!isUpload) {
      _doDownload(file, progressNotifier);
    }

    _openTransferBottomSheet(
      file: file,
      isUpload: isUpload,
      progressNotifier: progressNotifier,
    );
  }

  void _showMultiTransferSheet(
    List<(CloudFileItem, File)> pairs,
    int totalBytes,
  ) {
    _activeCancelToken = CancelToken();
    _isUploading = true;

    final firstItem = pairs.first.$1;
    final progressNotifier = ValueNotifier<_TransferProgress>(
      _TransferProgress(
        fraction: 0,
        transferred: 0,
        total: totalBytes,
        currentFile: 1,
        totalFiles: pairs.length,
        currentFileName: firstItem.name,
      ),
    );
    _activeProgressNotifier = progressNotifier;

    _doMultiUpload(pairs, totalBytes, progressNotifier);

    _openTransferBottomSheet(
      file: firstItem,
      isUpload: true,
      progressNotifier: progressNotifier,
    );
  }

  void _openTransferBottomSheet({
    required CloudFileItem file,
    required bool isUpload,
    required ValueNotifier<_TransferProgress> progressNotifier,
  }) {
    _transferSheetOpen = true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _TransferSheet(
          file: file,
          isUpload: isUpload,
          colors: Theme.of(context).extension<AppColors>()!,
          progressNotifier: progressNotifier,
          onClose: () {
            _transferSheetOpen = false;
            if (mounted) setState(() {});
            if (ctx.mounted) Navigator.of(ctx).pop();
            final p = progressNotifier.value;
            if (p.completed || p.failed || p.cancelled) {
              _activeProgressNotifier = null;
              _activeCancelToken = null;
            }
          },
          onCancel: _cancelActiveTransfer,
        );
      },
    ).whenComplete(() {
      _transferSheetOpen = false;
      if (mounted) setState(() {});
    });
  }

  void _reopenTransferSheet() {
    if (_activeProgressNotifier == null || _transferSheetOpen) return;
    _openTransferBottomSheet(
      file: CloudFileItem(
        id: 'active_transfer',
        name: _activeProgressNotifier!.value.currentFileName ?? 'Transfer',
        sizeBytes: _activeProgressNotifier!.value.total,
        ext: '',
        dateLabel: '',
        starred: false,
        kind: CloudFileKind.other,
      ),
      isUpload: _isUploading,
      progressNotifier: _activeProgressNotifier!,
    );
  }

  /// Send one file to whichever destination is selected.
  ///
  /// The single place the two upload paths diverge. Both report progress the
  /// same way and both return the finished row, so everything around them —
  /// the sheet, the notification, the cancel handling, the history entry — is
  /// shared rather than written twice and drifting apart.
  Future<CloudFileItem> _uploadOne(
    File file,
    CloudDestination destination, {
    required void Function(int sent, int total) onProgress,
  }) async {
    if (destination == CloudDestination.nas) {
      final uploaded = await ref.read(nasFilesServiceProvider).uploadFile(
            file,
            cancelToken: _activeCancelToken,
            onProgress: onProgress,
          );
      return CloudFileItem.fromNasFile(uploaded);
    }
    final uploaded = await ref.read(googleDriveServiceProvider).uploadFile(
          file,
          cancelToken: _activeCancelToken,
          onProgress: onProgress,
        );
    return CloudFileItem.fromDriveInfo(uploaded);
  }

  Future<void> _doUpload(
    File realFile,
    CloudFileItem tempItem,
    ValueNotifier<_TransferProgress> notifier,
  ) async {
    final tn = TransferNotification.instance;
    await tn.startForeground(
      title: 'Uploading ${tempItem.name}',
      body: 'Preparing upload…',
    );
    final destination = _destination;
    try {
      final newItem = await _uploadOne(
        realFile,
        destination,
        onProgress: (sent, total) {
          notifier.value = _TransferProgress(
            fraction: total > 0 ? sent / total : 0,
            transferred: sent,
            total: total,
          );
          final pct = total > 0 ? (sent * 100 / total).round() : 0;
          tn.show(
            title: 'Uploading ${tempItem.name}',
            body: '${_fmtBytes(sent)} / ${_fmtBytes(total)} · $pct%',
            pct: pct,
          );
        },
      );

      if (!mounted) return;

      setState(() {
        _files = _files.map((f) => f.id == tempItem.id ? newItem : f).toList();
        _addHistory(HistoryActionKind.upload,
            'Uploaded to ${destination.label}', newItem.name);
      });

      notifier.value = _TransferProgress(
        fraction: 1,
        transferred: newItem.sizeBytes,
        total: newItem.sizeBytes,
        completed: true,
      );
      _finishTransfer();
      tn.complete(
        title: 'Upload complete',
        body: '${newItem.name} uploaded to ${destination.label}',
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        TLog.w('Cloud', 'Upload cancelled: ${tempItem.name}');
        if (!mounted) return;
        setState(() {
          _files = _files.where((f) => f.id != tempItem.id).toList();
        });
        notifier.value = _TransferProgress(
          fraction: notifier.value.fraction,
          transferred: notifier.value.transferred,
          total: tempItem.sizeBytes,
          cancelled: true,
        );
        _finishTransfer();
        tn.cancel();
        return;
      }
      TLog.e('Cloud', 'Upload failed: ${tempItem.name}', error: e);
      if (!mounted) return;
      setState(() {
        _files = _files.where((f) => f.id != tempItem.id).toList();
      });
      notifier.value = _TransferProgress(
        fraction: 0,
        transferred: 0,
        total: tempItem.sizeBytes,
        failed: true,
        error: e.toString(),
      );
      _finishTransfer();
      tn.fail(
        title: 'Upload failed',
        body: '${tempItem.name} could not be uploaded',
      );
    } catch (e) {
      TLog.e('Cloud', 'Upload failed: ${tempItem.name}', error: e);
      if (!mounted) return;
      setState(() {
        _files = _files.where((f) => f.id != tempItem.id).toList();
      });
      notifier.value = _TransferProgress(
        fraction: 0,
        transferred: 0,
        total: tempItem.sizeBytes,
        failed: true,
        error: e.toString(),
      );
      _finishTransfer();
      tn.fail(
        title: 'Upload failed',
        body: '${tempItem.name} could not be uploaded',
      );
    }
  }

  void _cancelActiveTransfer() {
    _activeCancelToken?.cancel('User cancelled');
    _activeCancelToken = null;
    TransferNotification.instance.cancel();
    final n = _activeProgressNotifier;
    if (n != null) {
      final v = n.value;
      if (!v.completed && !v.failed && !v.cancelled) {
        n.value = _TransferProgress(
          fraction: v.fraction,
          transferred: v.transferred,
          total: v.total,
          cancelled: true,
          currentFile: v.currentFile,
          totalFiles: v.totalFiles,
          currentFileName: v.currentFileName,
        );
      }
    }
    _finishTransfer();
  }

  void _finishTransfer() {
    if (!_transferSheetOpen) {
      _activeProgressNotifier = null;
      _activeCancelToken = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _doMultiUpload(
    List<(CloudFileItem, File)> pairs,
    int totalBytes,
    ValueNotifier<_TransferProgress> notifier,
  ) async {
    final tn = TransferNotification.instance;
    await tn.startForeground(
      title: 'Uploading 1/${pairs.length} files',
      body: 'Preparing upload…',
    );
    var completedBytes = 0;
    var successCount = 0;
    var failCount = 0;
    // Captured once, before the loop: a batch of twenty files must all land in
    // the same place even if the switch is tapped while it is running.
    final destination = _destination;

    for (var i = 0; i < pairs.length; i++) {
      if (_activeCancelToken?.isCancelled == true) break;

      final (tempItem, realFile) = pairs[i];
      final fileBytes = tempItem.sizeBytes;

      notifier.value = _TransferProgress(
        fraction: totalBytes > 0 ? completedBytes / totalBytes : 0,
        transferred: completedBytes,
        total: totalBytes,
        currentFile: i + 1,
        totalFiles: pairs.length,
        currentFileName: tempItem.name,
      );

      try {
        final newItem = await _uploadOne(
          realFile,
          destination,
          onProgress: (sent, total) {
            final overallSent = completedBytes + sent;
            notifier.value = _TransferProgress(
              fraction: totalBytes > 0 ? overallSent / totalBytes : 0,
              transferred: overallSent,
              total: totalBytes,
              currentFile: i + 1,
              totalFiles: pairs.length,
              currentFileName: tempItem.name,
            );
            final pct =
                totalBytes > 0 ? (overallSent * 100 / totalBytes).round() : 0;
            tn.show(
              title: 'Uploading ${tempItem.name} (${i + 1}/${pairs.length})',
              body:
                  '${_fmtBytes(overallSent)} / ${_fmtBytes(totalBytes)} · $pct%',
              pct: pct,
            );
          },
        );

        if (!mounted) return;

        setState(() {
          _files =
              _files.map((f) => f.id == tempItem.id ? newItem : f).toList();
          _addHistory(HistoryActionKind.upload,
              'Uploaded to ${destination.label}', newItem.name);
        });

        completedBytes += fileBytes;
        successCount++;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          TLog.w('Cloud',
              'Multi-upload cancelled at file ${i + 1}/${pairs.length}');
          if (!mounted) return;
          setState(() {
            for (var j = i; j < pairs.length; j++) {
              _files =
                  _files.where((f) => f.id != pairs[j].$1.id).toList();
            }
          });
          notifier.value = _TransferProgress(
            fraction: totalBytes > 0 ? completedBytes / totalBytes : 0,
            transferred: completedBytes,
            total: totalBytes,
            cancelled: true,
            currentFile: i + 1,
            totalFiles: pairs.length,
          );
          _finishTransfer();
          tn.cancel();
          return;
        }

        failCount++;
        TLog.e('Cloud', 'Upload failed: ${tempItem.name}', error: e);
        if (!mounted) return;
        setState(() {
          _files = _files.where((f) => f.id != tempItem.id).toList();
        });
      } catch (e) {
        failCount++;
        TLog.e('Cloud', 'Upload failed: ${tempItem.name}', error: e);
        if (!mounted) return;
        setState(() {
          _files = _files.where((f) => f.id != tempItem.id).toList();
        });
      }
    }

    if (_activeCancelToken?.isCancelled == true) return;

    _finishTransfer();

    if (failCount > 0 && successCount == 0) {
      notifier.value = _TransferProgress(
        fraction: 0,
        transferred: completedBytes,
        total: totalBytes,
        failed: true,
        error: 'All ${pairs.length} files failed to upload',
        currentFile: pairs.length,
        totalFiles: pairs.length,
      );
      tn.fail(
        title: 'Upload failed',
        body: 'All ${pairs.length} files failed',
      );
    } else if (failCount > 0) {
      TLog.w('Cloud',
          'Multi-upload partial: $successCount ok, $failCount failed');
      notifier.value = _TransferProgress(
        fraction: totalBytes > 0 ? completedBytes / totalBytes : 0,
        transferred: completedBytes,
        total: totalBytes,
        completed: true,
        error: '$failCount of ${pairs.length} files failed',
        currentFile: pairs.length,
        totalFiles: pairs.length,
      );
      tn.complete(
        title: 'Upload partially complete',
        body: '$successCount uploaded, $failCount failed',
      );
    } else {
      TLog.i('Cloud', 'Multi-upload complete: $successCount files, '
          '${_fmtBytes(totalBytes)}');
      notifier.value = _TransferProgress(
        fraction: 1,
        transferred: totalBytes,
        total: totalBytes,
        completed: true,
        currentFile: pairs.length,
        totalFiles: pairs.length,
      );
      tn.complete(
        title: 'Upload complete',
        body: '$successCount files uploaded to Drive',
      );
    }
  }

  Future<void> _doDownload(
    CloudFileItem file,
    ValueNotifier<_TransferProgress> notifier,
  ) async {
    final tn = TransferNotification.instance;
    await tn.startForeground(
      title: 'Downloading ${file.name}',
      body: 'Preparing download…',
    );
    final destination = _destination;
    try {
      void report(int received, int total) {
        final t = total > 0 ? total : file.sizeBytes;
        notifier.value = _TransferProgress(
          fraction: t > 0 ? received / t : 0,
          transferred: received,
          total: t,
        );
        final pct = t > 0 ? (received * 100 / t).round() : 0;
        tn.show(
          title: 'Downloading ${file.name}',
          body: '${_fmtBytes(received)} / ${_fmtBytes(t)} · $pct%',
          pct: pct,
        );
      }

      if (destination == CloudDestination.nas) {
        await ref.read(nasFilesServiceProvider).downloadFile(
              file.name,
              cancelToken: _activeCancelToken,
              onProgress: report,
            );
      } else {
        await ref.read(googleDriveServiceProvider).downloadFile(
              file.id,
              file.name,
              cancelToken: _activeCancelToken,
              onProgress: report,
            );
      }

      if (!mounted) return;
      setState(() {
        _addHistory(HistoryActionKind.download, 'Downloaded file', file.name);
      });
      notifier.value = _TransferProgress(
        fraction: 1,
        transferred: file.sizeBytes,
        total: file.sizeBytes,
        completed: true,
      );
      _finishTransfer();
      tn.complete(
        title: 'Download complete',
        body: '${file.name} saved to device',
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        TLog.w('Cloud', 'Download cancelled: ${file.name}');
        notifier.value = _TransferProgress(
          fraction: notifier.value.fraction,
          transferred: notifier.value.transferred,
          total: file.sizeBytes,
          cancelled: true,
        );
        _finishTransfer();
        tn.cancel();
        return;
      }
      TLog.e('Cloud', 'Download failed: ${file.name}', error: e);
      notifier.value = _TransferProgress(
        fraction: 0,
        transferred: 0,
        total: file.sizeBytes,
        failed: true,
        error: e.toString(),
      );
      _finishTransfer();
      tn.fail(
        title: 'Download failed',
        body: '${file.name} could not be downloaded',
      );
    } catch (e) {
      TLog.e('Cloud', 'Download failed: ${file.name}', error: e);
      notifier.value = _TransferProgress(
        fraction: 0,
        transferred: 0,
        total: file.sizeBytes,
        failed: true,
        error: e.toString(),
      );
      _finishTransfer();
      tn.fail(
        title: 'Download failed',
        body: '${file.name} could not be downloaded',
      );
    }
  }

  void _startDownload(CloudFileItem file) {
    if (!PlatformCapabilities.canUseGoogleDrive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Downloading is coming soon on the web. Use the Android app for now.',
          ),
        ),
      );
      return;
    }
    if (_hasActiveTransfer) {
      _showTransferBusySnack();
      return;
    }
    _showTransferSheet(file: file, isUpload: false);
  }

  void _showTransferBusySnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(
          'A transfer is already in progress',
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        ),
        backgroundColor: Theme.of(context).extension<AppColors>()!.bg3,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _toggleStar(String id) async {
    // A WebDAV share has nowhere to record a star. The control is hidden for
    // NAS files, so this is only reachable via a stale callback — refusing is
    // better than lighting a star that the next refresh silently puts out.
    if (_destination == CloudDestination.nas) return;

    final idx = _files.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    final file = _files[idx];
    final newStarred = !file.starred;
    setState(() {
      _files = _files
          .map((f) => f.id == id ? f.copyWith(starred: newStarred) : f)
          .toList();
    });
    try {
      final driveService = ref.read(googleDriveServiceProvider);
      await driveService.toggleStar(id, starred: newStarred);
    } catch (e) {
      TLog.w('Cloud', 'Toggle star failed for $id: $e');
      if (!mounted) return;
      setState(() {
        _files = _files
            .map((f) => f.id == id ? f.copyWith(starred: !newStarred) : f)
            .toList();
      });
    }
  }

  Future<void> _deleteFile(String id) async {
    final idx = _files.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    final file = _files[idx];
    final destination = _destination;
    setState(() {
      _files = _files.where((f) => f.id != id).toList();
      _addHistory(HistoryActionKind.delete,
          'Removed from ${destination.label}', file.name);
    });
    try {
      if (destination == CloudDestination.nas) {
        await ref.read(nasFilesServiceProvider).deleteFile(file.name);
      } else {
        await ref.read(googleDriveServiceProvider).deleteFile(id);
      }
    } catch (e) {
      TLog.e('Cloud', 'Delete file failed for $id', error: e);
      if (!mounted) return;
      // The row was removed optimistically; reloading puts it back if the
      // delete did not actually happen, rather than leaving the list claiming
      // a file is gone when it is still on the share.
      _loadFiles();
    }
  }

  Future<void> _showFileActions(CloudFileItem file) async {
    final colors = Theme.of(context).extension<AppColors>()!;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.bg1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: colors.text4,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  _FileTypeIcon(kind: file.kind, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(file.name,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                color: colors.text, fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Text(_fmtBytes(file.sizeBytes),
                            style: GoogleFonts.plusJakartaSans(
                                color: colors.text2, fontSize: 12)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _ActionTile(
                  icon: LucideIcons.download, label: 'Download',
                  iconColor: AppColors.accent, colors: colors,
                  onTap: () { Navigator.pop(ctx); _startDownload(file); },
                ),
                _ActionTile(
                  icon: LucideIcons.star,
                  label: file.starred ? 'Remove star' : 'Star file',
                  iconColor: const Color(0xFFFBBF24), colors: colors,
                  filledStar: file.starred,
                  onTap: () { Navigator.pop(ctx); _toggleStar(file.id); },
                ),
                _ActionTile(
                  icon: LucideIcons.trash2, label: 'Delete',
                  iconColor: const Color(0xFFF87171), colors: colors,
                  danger: true,
                  onTap: () { Navigator.pop(ctx); _deleteFile(file.id); },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _hasActiveTransfer =>
      _activeProgressNotifier != null &&
      !(_activeProgressNotifier!.value.completed ||
          _activeProgressNotifier!.value.failed ||
          _activeProgressNotifier!.value.cancelled);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final view = ref.watch(cloudDestinationViewProvider);
    final isNas = view.isNas;

    var filtered = _files.where((f) => _matchesFilter(f, _filter)).toList();
    // Drive filters server-side via a query; the NAS folder arrives whole, so
    // its search is applied here.
    if (isNas && _searchQuery.isNotEmpty) {
      final needle = _searchQuery.toLowerCase();
      filtered = filtered
          .where((f) => f.name.toLowerCase().contains(needle))
          .toList();
    }
    final pctUsed = _totalGb > 0 ? (_usedGb / _totalGb * 100).round() : 0;

    return Column(
      children: [
        CompactHeader(
          title: 'Cloud',
          onAvatarTap: () => showSettingsModal(context, ref),
        ),
        // Above the TabBar rather than inside a tab, so it stays reachable from
        // both Files and History instead of scrolling away with the file list.
        const StatsLauncher(),
        // Pinned above the tabs, never in a menu. The whole point is that the
        // answer to "where is this about to go?" is on screen at the instant
        // the upload button is tapped, without having to remember it.
        DestinationSwitch(onChanged: (_) => _loadFiles()),
        Container(
          decoration: BoxDecoration(
            color: colors.headerBg,
            border: Border(bottom: BorderSide(color: colors.border, width: 1)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.accent, indicatorWeight: 2,
            labelColor: colors.text, unselectedLabelColor: colors.text3,
            labelStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w500),
            tabs: const [Tab(text: 'Files'), Tab(text: 'History')],
          ),
        ),
        if (_hasActiveTransfer && !_transferSheetOpen)
          _ActiveTransferBanner(
            colors: colors,
            progressNotifier: _activeProgressNotifier!,
            isUpload: _isUploading,
            onTap: _reopenTransferSheet,
            onCancel: _cancelActiveTransfer,
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _loading
                  ? _LoadingView(colors: colors)
                  : _error != null
                      ? _ErrorView(
                          colors: colors,
                          title: _errorTitle,
                          message: _error!,
                          detail: _errorDetail,
                          icon: _errorIcon,
                          onRetry: _loadFiles,
                        )
                      : _FilesTab(
                          colors: colors,
                          destination: view.selected,
                          nasRoot: view.nas.root,
                          usedFraction: _totalGb > 0 ? _usedGb / _totalGb : 0,
                          usedGb: _usedGb,
                          totalGb: _totalGb,
                          pctUsed: pctUsed,
                          filter: _filter,
                          onFilterChanged: (f) => setState(() => _filter = f),
                          files: filtered,
                          onUploadTap: _openUploadFlow,
                          onDownload: _startDownload,
                          onToggleStar: (id) => _toggleStar(id),
                          onDelete: (id) => _deleteFile(id),
                          onLongPress: _showFileActions,
                          onRefresh: _loadFiles,
                          searchController: _searchController,
                          onSearchChanged: _onSearchChanged,
                          isSearching: _isSearching,
                          hasMore: _nextPageToken != null,
                          loadingMore: _loadingMore,
                          onLoadMore: _loadMoreFiles,
                        ),
              _HistoryTab(colors: colors, history: _history),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Transfer progress model ──────────────────────────────────────────────────

class _TransferProgress {
  const _TransferProgress({
    required this.fraction,
    required this.transferred,
    required this.total,
    this.completed = false,
    this.failed = false,
    this.cancelled = false,
    this.error,
    this.currentFile = 1,
    this.totalFiles = 1,
    this.currentFileName,
  });

  final double fraction;
  final int transferred;
  final int total;
  final bool completed;
  final bool failed;
  final bool cancelled;
  final String? error;
  final int currentFile;
  final int totalFiles;
  final String? currentFileName;

  bool get isMultiFile => totalFiles > 1;
}

// ── Loading / Error views ────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.bg,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 40, height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          const SizedBox(height: 16),
          Text('Connecting to Google Drive…',
              style: GoogleFonts.plusJakartaSans(
                  color: colors.text3, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.colors,
    required this.title,
    required this.message,
    required this.icon,
    required this.onRetry,
    this.detail,
  });
  final AppColors colors;
  final String title;
  final String message;
  final String? detail;
  final IconData icon;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: colors.text4),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    color: colors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(color: colors.text3, fontSize: 13)),
            if (detail != null && detail!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.bg2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Text(detail!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jetBrainsMono(
                        color: colors.text4, fontSize: 11, height: 1.4)),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Active transfer banner (shown when sheet is dismissed) ───────────────────

class _ActiveTransferBanner extends StatelessWidget {
  const _ActiveTransferBanner({
    required this.colors,
    required this.progressNotifier,
    required this.isUpload,
    required this.onTap,
    required this.onCancel,
  });
  final AppColors colors;
  final ValueNotifier<_TransferProgress> progressNotifier;
  final bool isUpload;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_TransferProgress>(
      valueListenable: progressNotifier,
      builder: (context, p, _) {
        final pct = (p.fraction * 100).clamp(0.0, 100.0);
        final label = p.isMultiFile
            ? '${isUpload ? 'Uploading' : 'Downloading'} '
                '${p.currentFile}/${p.totalFiles}'
            : '${isUpload ? 'Uploading' : 'Downloading'} '
                '${p.currentFileName ?? 'file'}';

        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: p.fraction.clamp(0, 1),
                  strokeWidth: 2.5,
                  backgroundColor: colors.bg4,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            color: colors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtBytes(p.transferred)} / ${_fmtBytes(p.total)} · ${pct.toStringAsFixed(0)}%',
                      style: GoogleFonts.plusJakartaSans(
                          color: colors.text3, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text('Tap to expand',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCancel,
                child: Icon(LucideIcons.x, size: 18, color: colors.text3),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ── Files Tab ────────────────────────────────────────────────────────────────

class _FilesTab extends StatelessWidget {
  const _FilesTab({
    required this.colors,
    required this.destination,
    required this.nasRoot,
    required this.usedFraction,
    required this.usedGb,
    required this.totalGb,
    required this.pctUsed,
    required this.filter,
    required this.onFilterChanged,
    required this.files,
    required this.onUploadTap,
    required this.onDownload,
    required this.onToggleStar,
    required this.onDelete,
    required this.onLongPress,
    required this.onRefresh,
    required this.searchController,
    required this.onSearchChanged,
    required this.isSearching,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final AppColors colors;
  final CloudDestination destination;
  final String nasRoot;
  final double usedFraction;
  final double usedGb;
  final double totalGb;
  final int pctUsed;
  final FileFilter filter;
  final ValueChanged<FileFilter> onFilterChanged;
  final List<CloudFileItem> files;
  final VoidCallback onUploadTap;
  final void Function(CloudFileItem) onDownload;
  final void Function(String id) onToggleStar;
  final void Function(String id) onDelete;
  final void Function(CloudFileItem) onLongPress;
  final VoidCallback onRefresh;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool isSearching;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  bool get _isNas => destination == CloudDestination.nas;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.bg,
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        color: AppColors.accent,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification &&
                notification.metrics.extentAfter < 200 &&
                hasMore &&
                !loadingMore) {
              onLoadMore();
            }
            return false;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // Drive's quota card is Drive's. The NAS has 275 GB of pool free
              // and no per-user quota, so showing a ring against a 15 GB limit
              // there would be a made-up number — the real figure belongs to
              // the Stats dashboard, which measures it properly.
              if (!_isNas) ...[
                _StorageCapacityCard(
                  colors: colors,
                  usedFraction: usedFraction,
                  usedGb: usedGb,
                  totalGb: totalGb,
                  pctUsed: pctUsed,
                ),
                const SizedBox(height: 14),
              ],
              _UploadZone(
                colors: colors,
                onTap: onUploadTap,
                destination: destination,
                nasRoot: nasRoot,
              ),
              const SizedBox(height: 14),
              _SearchBar(
                colors: colors,
                controller: searchController,
                onChanged: onSearchChanged,
                isSearching: isSearching,
              ),
              const SizedBox(height: 14),
              _FilterChipsRow(
                colors: colors,
                selected: filter,
                onChanged: onFilterChanged,
              ),
              const SizedBox(height: 12),
              if (files.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      searchController.text.isNotEmpty
                          ? 'No files found for "${searchController.text}"'
                          : filter != FileFilter.all
                              ? 'No files match this filter'
                              // Naming the destination matters most here: an
                              // empty list is exactly what someone sees after
                              // uploading to the other one and looking in the
                              // wrong place.
                              : _isNas
                                  ? 'Nothing in ${nasRoot.isEmpty ? 'the NAS folder' : nasRoot} yet'
                                  : 'Nothing in Google Drive yet',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                          color: colors.text4, fontSize: 14),
                    ),
                  ),
                )
              else
                ...files.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FileRow(
                        file: f,
                        colors: colors,
                        // Starring is a Drive concept. There is nowhere on a
                        // WebDAV share to keep it, so the control is absent
                        // rather than present and inert.
                        onStar: _isNas ? null : () => onToggleStar(f.id),
                        onDownload: () => onDownload(f),
                        onDelete: () => onDelete(f.id),
                        onLongPress: () => onLongPress(f),
                      ),
                    )),
              if (loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.accent),
                      ),
                    ),
                  ),
                ),
              if (hasMore && !loadingMore)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(
                      'Scroll down for more files',
                      style: GoogleFonts.plusJakartaSans(
                          color: colors.text4, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Storage card ─────────────────────────────────────────────────────────────

class _StorageCapacityCard extends StatelessWidget {
  const _StorageCapacityCard({
    required this.colors,
    required this.usedFraction,
    required this.usedGb,
    required this.totalGb,
    required this.pctUsed,
  });
  final AppColors colors;
  final double usedFraction;
  final double usedGb;
  final double totalGb;
  final int pctUsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Row(children: [
        SizedBox(
          width: 96, height: 96,
          child: CustomPaint(
            painter: _StorageRingPainter(
              progress: usedFraction,
              trackColor: colors.bg4,
              progressColor: AppColors.accent,
            ),
            child: Center(
              child: Text('$pctUsed%',
                  style: GoogleFonts.plusJakartaSans(
                      color: colors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(LucideIcons.hardDrive, size: 14, color: colors.text3),
                const SizedBox(width: 6),
                Text('GOOGLE DRIVE',
                    style: GoogleFonts.plusJakartaSans(
                        color: colors.text3, fontSize: 11,
                        fontWeight: FontWeight.w600, letterSpacing: 1.2)),
              ]),
              const SizedBox(height: 6),
              Text(
                '${usedGb.toStringAsFixed(1)} GB of ${totalGb.toStringAsFixed(0)} GB used',
                style: GoogleFonts.plusJakartaSans(
                    color: colors.text, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text('${(totalGb - usedGb).toStringAsFixed(1)} GB free',
                  style: GoogleFonts.plusJakartaSans(
                      color: colors.text2, fontSize: 12)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Upload zone ──────────────────────────────────────────────────────────────

class _UploadZone extends StatefulWidget {
  const _UploadZone({
    required this.colors,
    required this.onTap,
    required this.destination,
    required this.nasRoot,
  });
  final AppColors colors;
  final VoidCallback onTap;
  final CloudDestination destination;
  final String nasRoot;

  @override
  State<_UploadZone> createState() => _UploadZoneState();
}

class _UploadZoneState extends State<_UploadZone> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final cyan = AppColors.accentCyan.withValues(alpha: 0.45);
    final isNas = widget.destination == CloudDestination.nas;
    // Named on the button itself, not only on the switch above it. This is the
    // control the finger is actually on, and it is the last thing read before
    // the file picker takes over the screen.
    final target = isNas
        ? (widget.nasRoot.isEmpty ? 'the NAS' : widget.nasRoot)
        : 'Google Drive';
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.98),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: CustomPaint(
          painter: _DashedRRectPainter(color: cyan, radius: 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: AppColors.accentCyan.withValues(alpha: 0.04),
            ),
            child: Column(children: [
              Icon(isNas ? LucideIcons.hardDrive : LucideIcons.uploadCloud,
                  size: 40, color: AppColors.accentCyan),
              const SizedBox(height: 12),
              // Cross-faded rather than swapped, so flipping the switch reads
              // as this control changing its mind about where it points.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text('Tap to upload files to $target',
                    key: ValueKey(target),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              Text(
                  isNas
                      ? 'Any file type · stored on your own hardware'
                      : 'PDF, DOCX, XLSX, JPG, PNG, MP4, ZIP',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      color: c.text3, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Search bar ──────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.colors,
    required this.controller,
    required this.onChanged,
    required this.isSearching,
  });
  final AppColors colors;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(LucideIcons.search, size: 18, color: colors.text4),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: GoogleFonts.plusJakartaSans(
                color: colors.text,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Search files in Drive…',
                hintStyle: GoogleFonts.plusJakartaSans(
                  color: colors.text4,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (isSearching)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
            )
          else if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(LucideIcons.x, size: 16, color: colors.text4),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Filter chips ─────────────────────────────────────────────────────────────

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    required this.colors, required this.selected, required this.onChanged});
  final AppColors colors;
  final FileFilter selected;
  final ValueChanged<FileFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = <(FileFilter, String)>[
      (FileFilter.all, 'All'),
      (FileFilter.documents, 'Documents'),
      (FileFilter.images, 'Images'),
      (FileFilter.videos, 'Videos'),
      (FileFilter.starred, 'Starred'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (f, label) in items)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w500,
                      color: selected == f ? colors.text : colors.text2)),
              selected: selected == f,
              onSelected: (_) => onChanged(f),
              backgroundColor: colors.bg2,
              selectedColor: AppColors.accent.withValues(alpha: 0.2),
              checkmarkColor: AppColors.accent,
              side: BorderSide(color: colors.border),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
      ]),
    );
  }
}

// ── File type icon ───────────────────────────────────────────────────────────

class _FileTypeIcon extends StatelessWidget {
  const _FileTypeIcon({required this.kind, this.size = 40, this.colors});
  final CloudFileKind kind;
  final double size;
  final AppColors? colors;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? Theme.of(context).extension<AppColors>()!;
    final bg = _iconColorForKind(kind, c).withValues(alpha: 0.15);
    final br = _iconColorForKind(kind, c).withValues(alpha: 0.35);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: br),
      ),
      child: Icon(_iconForKind(kind), size: size * 0.48,
          color: _iconColorForKind(kind, c)),
    );
  }
}

// ── File thumbnail with image preview ────────────────────────────────────────

class _FileThumbnail extends StatelessWidget {
  const _FileThumbnail({
    required this.file,
    required this.colors,
    required this.size,
  });
  final CloudFileItem file;
  final AppColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (file.isImage && file.thumbnailLink != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            file.thumbnailLink!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _FileTypeIcon(kind: file.kind, size: size, colors: colors),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                width: size,
                height: size,
                color: colors.bg3,
                child: Center(
                  child: SizedBox(
                    width: size * 0.4,
                    height: size * 0.4,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.accent),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return _FileTypeIcon(kind: file.kind, size: size, colors: colors);
  }
}

// ── File row ─────────────────────────────────────────────────────────────────

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file, required this.colors,
    required this.onDownload, required this.onStar,
    required this.onDelete, required this.onLongPress,
  });
  final CloudFileItem file;
  final AppColors colors;
  final VoidCallback onDownload;

  /// Null where starring has nowhere to be stored — the button is then left
  /// out rather than shown disabled, because a greyed star invites a tap that
  /// will never do anything.
  final VoidCallback? onStar;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey<String>(file.id),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          onDelete();
        } else if (direction == DismissDirection.startToEnd) {
          onDownload();
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(14)),
        child: Icon(LucideIcons.download, color: colors.text),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF87171).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14)),
        child: Icon(LucideIcons.trash2, color: colors.text),
      ),
      child: Material(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              _FileThumbnail(file: file, colors: colors, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            color: colors.text, fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${_fmtBytes(file.sizeBytes)} · ${file.dateLabel}',
                        style: GoogleFonts.plusJakartaSans(
                            color: colors.text3, fontSize: 11)),
                  ],
                ),
              ),
              if (onStar != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onStar,
                  icon: Icon(LucideIcons.star, size: 20,
                      color: file.starred
                          ? const Color(0xFFFBBF24) : colors.text4,
                      fill: file.starred ? 1 : 0),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDownload,
                icon: Icon(LucideIcons.download, size: 20, color: colors.text2),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: Icon(LucideIcons.trash2, size: 20, color: colors.text4),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Action tile (bottom sheet) ───────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon, required this.label,
    required this.iconColor, required this.colors,
    required this.onTap, this.danger = false, this.filledStar = false,
  });
  final IconData icon;
  final String label;
  final Color iconColor;
  final AppColors colors;
  final VoidCallback onTap;
  final bool danger;
  final bool filledStar;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: iconColor, fill: filledStar ? 1 : 0),
      ),
      title: Text(label,
          style: GoogleFonts.plusJakartaSans(
              color: danger ? const Color(0xFFF87171) : colors.text,
              fontWeight: FontWeight.w600, fontSize: 15)),
      onTap: onTap,
    );
  }
}

// ── History tab ──────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.colors, required this.history});
  final AppColors colors;
  final List<HistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return ColoredBox(
        color: colors.bg,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.history, size: 48, color: colors.text4),
            const SizedBox(height: 12),
            Text('No history yet',
                style: GoogleFonts.plusJakartaSans(
                    color: colors.text3, fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Uploads, downloads, and sync will appear here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    color: colors.text5, fontSize: 13)),
          ]),
        ),
      );
    }

    final now = DateTime.now();
    final sorted = List<HistoryEntry>.from(history)
      ..sort((a, b) => b.at.compareTo(a.at));
    final groups = <String, List<HistoryEntry>>{};
    for (final e in sorted) {
      final key = _groupLabelForDate(e.at, now);
      groups.putIfAbsent(key, () => []).add(e);
    }

    return ColoredBox(
      color: colors.bg,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final key = groups.keys.elementAt(i);
          final entries = groups[key]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 8, top: i == 0 ? 0 : 16),
                child: Text(key,
                    style: GoogleFonts.plusJakartaSans(
                        color: colors.text3, fontSize: 11,
                        fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
              ...entries.map((e) => _HistoryTile(entry: e, colors: colors)),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.colors});
  final HistoryEntry entry;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final accent = _historyAccent(entry.kind);
    final timeStr = DateFormat.jm().format(entry.at);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.35))),
            child: Icon(_historyIcon(entry.kind), color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    style: GoogleFonts.plusJakartaSans(
                        color: colors.text, fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(entry.fileName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        color: colors.text2, fontSize: 12)),
                const SizedBox(height: 2),
                Text(timeStr,
                    style: GoogleFonts.plusJakartaSans(
                        color: colors.text4, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transfer bottom sheet ────────────────────────────────────────────────────

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({
    required this.file,
    required this.isUpload,
    required this.colors,
    required this.progressNotifier,
    required this.onClose,
    this.onCancel,
  });
  final CloudFileItem file;
  final bool isUpload;
  final AppColors colors;
  final ValueNotifier<_TransferProgress> progressNotifier;
  final VoidCallback onClose;
  final VoidCallback? onCancel;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  double _displayedSpeed = 0;
  int _lastTransferred = 0;
  DateTime _lastTime = DateTime.now();
  Timer? _speedTimer;
  bool _autoCloseScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.progressNotifier.addListener(_onProgress);
    _speedTimer = Timer.periodic(const Duration(milliseconds: 500), _updateSpeed);
  }

  void _onProgress() {
    if (mounted) setState(() {});
    final p = widget.progressNotifier.value;
    if ((p.completed || p.cancelled) && !_autoCloseScheduled) {
      _autoCloseScheduled = true;
      Future<void>.delayed(
        Duration(milliseconds: p.cancelled ? 1500 : 900),
        () {
          if (mounted) widget.onClose();
        },
      );
    }
  }

  void _updateSpeed(Timer _) {
    final p = widget.progressNotifier.value;
    final now = DateTime.now();
    final dt = now.difference(_lastTime).inMilliseconds / 1000.0;
    if (dt > 0) {
      final delta = p.transferred - _lastTransferred;
      final speedBps = delta / dt;
      _displayedSpeed = speedBps / (1024 * 1024);
    }
    _lastTransferred = p.transferred;
    _lastTime = now;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    widget.progressNotifier.removeListener(_onProgress);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final p = widget.progressNotifier.value;
    final pct = (p.fraction * 100).clamp(0.0, 100.0);
    final remaining = (p.total - p.transferred).clamp(0, p.total);
    final etaSec = _displayedSpeed > 0
        ? remaining / (_displayedSpeed * 1024 * 1024) : 0.0;

    final isDone = p.completed || p.failed || p.cancelled;
    final statusText = p.cancelled
        ? 'Cancelled'
        : p.failed
            ? 'Failed'
            : p.completed
                ? 'Complete!'
                : widget.isUpload
                    ? 'Uploading'
                    : 'Downloading';
    final statusColor = p.cancelled
        ? const Color(0xFFFBBF24)
        : p.failed
            ? const Color(0xFFF87171)
            : p.completed
                ? const Color(0xFF34D399)
                : c.text;
    final barColor = p.cancelled
        ? const Color(0xFFFBBF24)
        : p.failed
            ? const Color(0xFFF87171)
            : p.completed
                ? const Color(0xFF34D399)
                : AppColors.accent;

    final displayName = p.currentFileName ?? widget.file.name;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: c.bg1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(statusText,
                  style: GoogleFonts.plusJakartaSans(
                      color: statusColor,
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (p.isMultiFile) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${p.currentFile}/${p.totalFiles}',
                    style: GoogleFonts.plusJakartaSans(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: widget.onClose,
                icon: Icon(LucideIcons.x, color: c.text3, size: 22)),
            ]),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FileTypeIcon(kind: widget.file.kind, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              color: c.text, fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                          p.isMultiFile
                              ? '${p.totalFiles} files'
                              : widget.file.ext.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                              color: c.text3, fontSize: 11,
                              letterSpacing: 0.8)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: p.fraction.clamp(0, 1),
                minHeight: 8,
                backgroundColor: c.bg4,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${pct.toStringAsFixed(0)}%',
                  style: GoogleFonts.plusJakartaSans(
                      color: c.text2, fontSize: 12, fontWeight: FontWeight.w600)),
              Text('${_fmtBytes(p.transferred)} / ${_fmtBytes(p.total)}',
                  style: GoogleFonts.plusJakartaSans(
                      color: c.text3, fontSize: 11)),
            ]),
            if ((p.failed || p.cancelled) && p.error != null) ...[
              const SizedBox(height: 8),
              Text(p.error!,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFF87171), fontSize: 11)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _MetricBlock(
                    label: 'Speed',
                    value: _displayedSpeed.toStringAsFixed(1),
                    unit: 'MB/s',
                    valueColor: AppColors.accentCyan, colors: c),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricBlock(
                    label: 'ETA',
                    value: isDone ? '00:00' : _fmtEta(etaSec),
                    unit: '',
                    valueColor: AppColors.vaultPurple, colors: c),
              ),
            ]),
            const SizedBox(height: 16),
            if (isDone)
              OutlinedButton(
                onPressed: widget.onClose,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                    p.completed
                        ? 'Done'
                        : p.cancelled
                            ? 'Dismissed'
                            : 'Close',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 13,
                        letterSpacing: 0.5)),
              )
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.onCancel?.call();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF87171),
                      side: const BorderSide(color: Color(0xFFF87171)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 13,
                            letterSpacing: 0.5)),
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label, required this.value,
    required this.unit, required this.valueColor, required this.colors,
  });
  final String label;
  final String value;
  final String unit;
  final Color valueColor;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                  color: colors.text3, fontSize: 9,
                  fontWeight: FontWeight.w600, letterSpacing: 1.1)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: GoogleFonts.plusJakartaSans(
                      color: valueColor, fontSize: 22,
                      fontWeight: FontWeight.w800)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit,
                    style: GoogleFonts.plusJakartaSans(
                        color: colors.text2, fontSize: 12)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
