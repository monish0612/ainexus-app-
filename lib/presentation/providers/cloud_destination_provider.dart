import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/di/injection.dart';
import '../../core/services/telegram_logger.dart';
import '../../data/services/nas_files_service.dart';
import '../../domain/entities/nas_file.dart';

/// Where the Cloud tab reads from and writes to.
///
/// One at a time, wholesale: the Files tab shows the contents of the selected
/// destination and nothing else, and an upload goes there. A merged view would
/// be prettier and would also make "where is my file?" unanswerable — two
/// places named the same thing, with different contents, and no way to tell
/// from a row which one you are looking at.
enum CloudDestination {
  drive,
  nas;

  String get label => this == CloudDestination.drive ? 'Google Drive' : 'NAS';

  String get shortLabel => this == CloudDestination.drive ? 'Drive' : 'NAS';
}

/// The selected destination, remembered across launches.
///
/// Persisted because the choice is a standing preference about where this
/// person's files live, not a per-session mode. Resetting to Drive on every
/// launch would quietly send the next upload somewhere he did not choose —
/// exactly the failure this feature has to avoid.
class CloudDestinationNotifier extends StateNotifier<CloudDestination> {
  CloudDestinationNotifier(this._prefs) : super(_read(_prefs));

  static const _key = 'cloud_destination';

  final SharedPreferences _prefs;

  static CloudDestination _read(SharedPreferences prefs) {
    return prefs.getString(_key) == 'nas'
        ? CloudDestination.nas
        : CloudDestination.drive;
  }

  Future<void> select(CloudDestination next) async {
    if (state == next) return;
    state = next;
    try {
      await _prefs.setString(_key, next == CloudDestination.nas ? 'nas' : 'drive');
    } catch (e) {
      // The switch has already taken effect in memory; failing to remember it
      // for next launch is not worth interrupting him over.
      TLog.w('Cloud', 'could not persist storage destination: $e');
    }
  }
}

final cloudDestinationProvider =
    StateNotifierProvider<CloudDestinationNotifier, CloudDestination>(
  (ref) => CloudDestinationNotifier(ref.watch(sharedPreferencesProvider)),
);

/// Whether the NAS destination can be offered, refreshed on demand.
///
/// Kept separate from the selection so the switch can render the NAS side as
/// visibly unavailable *before* it is tapped, rather than accepting the tap and
/// failing at upload time with the file already chosen.
class NasAvailabilityNotifier extends StateNotifier<NasStorageStatus> {
  NasAvailabilityNotifier(this._service) : super(NasStorageStatus.unknown) {
    refresh();
  }

  final NasFilesService _service;
  bool _inFlight = false;

  Future<void> refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final next = await _service.status();
      if (mounted) state = next;
    } finally {
      _inFlight = false;
    }
  }
}

final nasAvailabilityProvider =
    StateNotifierProvider<NasAvailabilityNotifier, NasStorageStatus>(
  (ref) => NasAvailabilityNotifier(ref.watch(nasFilesServiceProvider)),
);

/// Everything the destination switch needs in one read.
@immutable
class CloudDestinationView {
  const CloudDestinationView({
    required this.selected,
    required this.nas,
  });

  final CloudDestination selected;
  final NasStorageStatus nas;

  bool get isNas => selected == CloudDestination.nas;

  /// True when the NAS is selected but cannot currently be written to. The
  /// Files tab uses this to explain itself instead of showing an empty list
  /// that looks like "you have no files".
  bool get nasSelectedButUnusable => isNas && !nas.isReady;
}

final cloudDestinationViewProvider = Provider<CloudDestinationView>((ref) {
  return CloudDestinationView(
    selected: ref.watch(cloudDestinationProvider),
    nas: ref.watch(nasAvailabilityProvider),
  );
});
