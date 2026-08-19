import 'package:flutter/foundation.dart';

/// Models for the Cloud > Stats dashboard.
///
/// Every field here is null-tolerant, and that is a deliberate contract rather
/// than defensive habit. `nas-status.py` collects each section of its snapshot
/// inside its own try/except and sends `null` for anything that failed, so that
/// a `smartctl` hiccup costs one row instead of the whole screen. If these
/// models required their fields, that design would be undone at the last step:
/// the phone would throw on parse and show nothing at all.
///
/// So the rule throughout is that a missing number stays missing. Nothing here
/// substitutes a zero for an unknown, because "0 °C" and "we could not read the
/// temperature" are different statements and only one of them is true.

/// Why the dashboard is not showing live figures.
enum NasOfflineReason {
  /// Nothing answered on the NAS's status port — almost always "it is off".
  unreachable,

  /// It answered too slowly. Up, but wedged or very busy.
  timeout,

  /// It rejected the API's token. A configuration fault, not an outage.
  auth,

  /// The API has no NAS token configured, so there is nothing to ask.
  notConfigured,

  /// It answered with something that was not a valid snapshot.
  badPayload,

  /// Reported offline without saying why.
  unknown;

  static NasOfflineReason parse(Object? raw) => switch (raw?.toString()) {
        'unreachable' => NasOfflineReason.unreachable,
        'timeout' => NasOfflineReason.timeout,
        'auth' => NasOfflineReason.auth,
        'not_configured' => NasOfflineReason.notConfigured,
        'bad_payload' => NasOfflineReason.badPayload,
        _ => NasOfflineReason.unknown,
      };

  /// One calm line for the offline banner.
  ///
  /// A switched-off NAS is the most likely reason by far and is not a fault, so
  /// it reads as a statement of fact. The two that *are* faults say what to do
  /// without turning the screen into an error dialog.
  String get message => switch (this) {
        NasOfflineReason.unreachable => 'Your NAS is switched off or off the network.',
        NasOfflineReason.timeout => 'Your NAS is not responding right now.',
        NasOfflineReason.auth =>
          'The server was refused by your NAS. Its status token needs updating.',
        NasOfflineReason.notConfigured =>
          'Live stats are not configured on the server yet.',
        NasOfflineReason.badPayload => 'Your NAS sent a reading that could not be read.',
        NasOfflineReason.unknown => 'Live stats are unavailable right now.',
      };
}

/// How much headroom the NAS has, using the same thresholds `reporter.py`
/// alerts on so the phone and Telegram can never disagree about "low".
enum MemoryPressure {
  ok,
  low,
  critical,
  unknown;

  static MemoryPressure parse(Object? raw) => switch (raw?.toString()) {
        'ok' => MemoryPressure.ok,
        'low' => MemoryPressure.low,
        'critical' => MemoryPressure.critical,
        _ => MemoryPressure.unknown,
      };
}

// ── parse helpers ───────────────────────────────────────────────────────────
// Tolerant on purpose: JSON gives an int where a double is expected and vice
// versa depending on whether a value happened to land on a whole number, and a
// dashboard must not fail on `37` where it expected `37.0`.

double? _d(Object? v) => switch (v) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

int? _i(Object? v) => switch (v) {
      final num n => n.round(),
      final String s => int.tryParse(s),
      _ => null,
    };

bool? _b(Object? v) => switch (v) {
      final bool b => b,
      'true' => true,
      'false' => false,
      _ => null,
    };

String? _s(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

Map<String, dynamic>? _m(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return const [];
  final out = <T>[];
  for (final e in v) {
    final m = _m(e);
    if (m != null) out.add(parse(m));
  }
  return out;
}

// ── sections ────────────────────────────────────────────────────────────────

@immutable
class NasCpu {
  const NasCpu({this.cores, this.pct, this.load1, this.load5, this.load15});

  final int? cores;

  /// Busy percentage across all cores, or null on the very first sample after
  /// the daemon starts — a percentage is a difference between two readings and
  /// does not exist until there are two.
  final double? pct;
  final double? load1;
  final double? load5;
  final double? load15;

  factory NasCpu.fromJson(Map<String, dynamic> m) => NasCpu(
        cores: _i(m['cores']),
        pct: _d(m['pct']),
        load1: _d(m['load1']),
        load5: _d(m['load5']),
        load15: _d(m['load15']),
      );

  /// Load relative to core count, which is the figure that actually means
  /// something: 3.5 is comfortable on 8 cores and drowning on 2.
  double? get loadPerCore {
    final c = cores;
    final l = load1;
    if (c == null || c <= 0 || l == null) return null;
    return l / c;
  }
}

@immutable
class NasMemory {
  const NasMemory({
    this.totalMb,
    this.availableMb,
    this.freeMb,
    this.arcMb,
    this.arcCapMb,
    this.pressure = MemoryPressure.unknown,
  });

  final int? totalMb;
  final int? availableMb;
  final int? freeMb;

  /// What ZFS is holding for its cache. Capped at 1536 MB on this box; null
  /// when no explicit cap is set, which is not the same as a cap of zero.
  final int? arcMb;
  final int? arcCapMb;
  final MemoryPressure pressure;

  factory NasMemory.fromJson(Map<String, dynamic> m) => NasMemory(
        totalMb: _i(m['total_mb']),
        availableMb: _i(m['available_mb']),
        freeMb: _i(m['free_mb']),
        arcMb: _i(m['arc_mb']),
        arcCapMb: _i(m['arc_cap_mb']),
        pressure: MemoryPressure.parse(m['pressure']),
      );

  /// Used against total, from MemAvailable rather than MemFree.
  ///
  /// MemFree would read as ~75% used on a healthy machine, because ZFS
  /// deliberately fills spare memory with cache it will hand straight back.
  /// MemAvailable is the figure that answers "is anything actually short".
  double? get usedPct {
    final t = totalMb;
    final a = availableMb;
    if (t == null || a == null || t <= 0) return null;
    return (((t - a) / t) * 100).clamp(0, 100).toDouble();
  }

  double? get arcFillPct {
    final c = arcCapMb;
    final a = arcMb;
    if (c == null || a == null || c <= 0) return null;
    return ((a / c) * 100).clamp(0, 100).toDouble();
  }
}

@immutable
class NasPool {
  const NasPool({
    this.name,
    this.health,
    this.sizeBytes,
    this.usedBytes,
    this.freeBytes,
    this.usedPct,
    this.role,
  });

  final String? name;
  final String? health;
  final int? sizeBytes;
  final int? usedBytes;
  final int? freeBytes;
  final int? usedPct;

  /// `main` or `backup_usb`. Used so the UI can say "the USB backup disk"
  /// instead of presenting Backup as if it were more room for films.
  final String? role;

  factory NasPool.fromJson(Map<String, dynamic> m) => NasPool(
        name: _s(m['name']),
        health: _s(m['health']),
        sizeBytes: _i(m['size_bytes']),
        usedBytes: _i(m['used_bytes']),
        freeBytes: _i(m['free_bytes']),
        usedPct: _i(m['used_pct']),
        role: _s(m['role']),
      );

  bool get isHealthy => health == 'ONLINE';
  bool get isBackup => role == 'backup_usb';

  /// 80% is a real ZFS threshold, not a round number: past it, copy-on-write
  /// allocation fragments and writes slow down. TrueNAS warns at the same
  /// point, so the phone and the appliance agree.
  bool get isCritical => (usedPct ?? 0) >= 80;
  bool get isWarning => (usedPct ?? 0) >= 70 && !isCritical;
}

@immutable
class NasMovies {
  const NasMovies({
    this.dataset,
    this.path,
    this.usedBytes,
    this.availBytes,
    this.referBytes,
    this.headlineFreeGb,
    this.note,
  });

  final String? dataset;
  final String? path;
  final int? usedBytes;
  final int? availBytes;
  final int? referBytes;

  /// The one number this whole screen exists to answer: how much more film
  /// will fit.
  final int? headlineFreeGb;

  /// The 14-day snapshot caveat, carried with the number rather than hardcoded
  /// in the UI so the daemon stays the single source of truth for its meaning.
  final String? note;

  factory NasMovies.fromJson(Map<String, dynamic> m) => NasMovies(
        dataset: _s(m['dataset']),
        path: _s(m['path']),
        usedBytes: _i(m['used_bytes']),
        availBytes: _i(m['avail_bytes']),
        referBytes: _i(m['refer_bytes']),
        headlineFreeGb: _i(m['headline_free_gb']),
        note: _s(m['note']),
      );

  double? get usedPct {
    final u = usedBytes;
    final a = availBytes;
    if (u == null || a == null) return null;
    final total = u + a;
    if (total <= 0) return null;
    return ((u / total) * 100).clamp(0, 100).toDouble();
  }
}

@immutable
class NasSnapshotHold {
  const NasSnapshotHold({this.countStorage, this.heldBytes});

  final int? countStorage;

  /// Space held by snapshots of deleted data. Without this the app looks like
  /// it is lying: you delete a film and free space does not move for 14 days.
  final int? heldBytes;

  factory NasSnapshotHold.fromJson(Map<String, dynamic> m) => NasSnapshotHold(
        countStorage: _i(m['count_storage']),
        heldBytes: _i(m['held_bytes']),
      );

  /// Worth a sentence on screen only once it is a meaningful amount of space.
  bool get isMeaningful => (heldBytes ?? 0) > 1024 * 1024 * 1024;

  double get heldGb => (heldBytes ?? 0) / (1024 * 1024 * 1024);
}

@immutable
class NasDisk {
  const NasDisk({this.name, this.role, this.tempC, this.ok});

  final String? name;
  final String? role;
  final int? tempC;
  final bool? ok;

  factory NasDisk.fromJson(Map<String, dynamic> m) => NasDisk(
        name: _s(m['name']),
        role: _s(m['role']),
        tempC: _i(m['temp_c']),
        ok: _b(m['ok']),
      );

  /// Consumer SSDs throttle around 70 °C, and heat is the main thing that
  /// shortens their life in a nearly fanless box.
  bool get isHot => (tempC ?? 0) >= 72;
  bool get isWarm => (tempC ?? 0) >= 65 && !isHot;
  bool get isFailing => ok == false;
}

@immutable
class NasServices {
  const NasServices({
    this.jellyfin,
    this.nextcloud,
    this.caddy,
    this.smb,
    this.mediaWatch,
    this.liveTv,
  });

  final bool? jellyfin;
  final bool? nextcloud;
  final bool? caddy;
  final bool? smb;
  final bool? mediaWatch;

  /// A string, not a bool, and deliberately so. Live TV was switched off on
  /// purpose; showing it as `false` would look like a fault and eventually get
  /// "fixed" by someone starting Threadfin again.
  final String? liveTv;

  factory NasServices.fromJson(Map<String, dynamic> m) => NasServices(
        jellyfin: _b(m['jellyfin']),
        nextcloud: _b(m['nextcloud']),
        caddy: _b(m['caddy']),
        smb: _b(m['smb']),
        mediaWatch: _b(m['media_watch']),
        liveTv: _s(m['livetv']),
      );

  bool get liveTvOffByChoice => liveTv == 'off_by_choice';
}

@immutable
class NasPlaybackItem {
  const NasPlaybackItem({this.title, this.where, this.method});

  final String? title;

  /// `home` or `outside`. No usernames and no IP addresses ever cross the
  /// tunnel, so this is all the app knows about who is watching.
  final String? where;

  /// `DirectPlay`, `DirectStream` or `Transcode`. Transcoding is called out
  /// because this GPU struggles with HDR-to-SDR, and it is nearly always the
  /// answer to "why is playback stuttering".
  final String? method;

  factory NasPlaybackItem.fromJson(Map<String, dynamic> m) => NasPlaybackItem(
        title: _s(m['title']),
        where: _s(m['where']),
        method: _s(m['method']),
      );

  bool get isTranscoding => method == 'Transcode';
  bool get isAtHome => where == 'home';
}

@immutable
class NasPlayback {
  const NasPlayback({this.count, this.items = const []});

  final int? count;
  final List<NasPlaybackItem> items;

  factory NasPlayback.fromJson(Map<String, dynamic> m) => NasPlayback(
        count: _i(m['count']),
        items: _list(m['items'], NasPlaybackItem.fromJson),
      );

  bool get anyTranscoding => items.any((i) => i.isTranscoding);
}

@immutable
class NasHealth {
  const NasHealth({this.stagesOk, this.stagesTotal, this.failing = const []});

  final int? stagesOk;
  final int? stagesTotal;
  final List<String> failing;

  factory NasHealth.fromJson(Map<String, dynamic> m) => NasHealth(
        stagesOk: _i(m['stages_ok']),
        stagesTotal: _i(m['stages_total']),
        failing: (m['failing'] is List)
            ? (m['failing'] as List).whereType<String>().toList()
            : const [],
      );

  bool get allPassing =>
      stagesOk != null && stagesTotal != null && stagesOk == stagesTotal;
}

// ── the snapshot ────────────────────────────────────────────────────────────

@immutable
class NasSnapshot {
  const NasSnapshot({
    this.at,
    this.host,
    this.version,
    this.uptimeS,
    this.cpu,
    this.memory,
    this.pools = const [],
    this.movies,
    this.snapshots,
    this.disks = const [],
    this.services,
    this.playback,
    this.health,
  });

  final int? at;
  final String? host;
  final String? version;
  final int? uptimeS;
  final NasCpu? cpu;
  final NasMemory? memory;
  final List<NasPool> pools;
  final NasMovies? movies;
  final NasSnapshotHold? snapshots;
  final List<NasDisk> disks;
  final NasServices? services;
  final NasPlayback? playback;
  final NasHealth? health;

  factory NasSnapshot.fromJson(Map<String, dynamic> m) {
    final cpu = _m(m['cpu']);
    final memory = _m(m['memory']);
    final movies = _m(m['movies']);
    final snaps = _m(m['snapshots']);
    final services = _m(m['services']);
    final playback = _m(m['playback']);
    final health = _m(m['health']);
    return NasSnapshot(
      at: _i(m['at']),
      host: _s(m['host']),
      version: _s(m['version']),
      uptimeS: _i(m['uptime_s']),
      cpu: cpu == null ? null : NasCpu.fromJson(cpu),
      memory: memory == null ? null : NasMemory.fromJson(memory),
      pools: _list(m['pools'], NasPool.fromJson),
      movies: movies == null ? null : NasMovies.fromJson(movies),
      snapshots: snaps == null ? null : NasSnapshotHold.fromJson(snaps),
      disks: _list(m['disks'], NasDisk.fromJson),
      services: services == null ? null : NasServices.fromJson(services),
      playback: playback == null ? null : NasPlayback.fromJson(playback),
      health: health == null ? null : NasHealth.fromJson(health),
    );
  }

  NasPool? get mainPool =>
      pools.where((p) => p.role == 'main').firstOrNull ?? pools.firstOrNull;

  NasPool? get backupPool => pools.where((p) => p.isBackup).firstOrNull;

  bool get anyPoolUnhealthy => pools.any((p) => !p.isHealthy);
  bool get anyDiskHot => disks.any((d) => d.isHot);
  bool get anyDiskFailing => disks.any((d) => d.isFailing);
}

// ── the VPS ─────────────────────────────────────────────────────────────────

@immutable
class VpsLive {
  const VpsLive({
    this.cpuPct,
    this.cores,
    this.load1,
    this.load5,
    this.load15,
    this.memPct,
    this.memTotalGb,
    this.memFreeGb,
    this.diskPct,
    this.diskTotalGb,
    this.diskFreeGb,
    this.uptimeS,
    this.state,
    this.stateFrom,
    this.reachable,
    this.stealPct,
    this.throttled,
    this.conditions = const [],
    this.containers,
    this.running,
    this.ageS,
    this.stale,
    this.planName,
    this.vcpus,
    this.planRamMb,
    this.planDiskMb,
    this.hostname,
    this.billing,
  });

  // Measured by the API process itself, so these stay live even when the NAS
  // is off — the machine answering the request is self-evidently up.
  final double? cpuPct;
  final int? cores;
  final double? load1;
  final double? load5;
  final double? load15;
  final double? memPct;
  final double? memTotalGb;
  final double? memFreeGb;
  final double? diskPct;
  final double? diskTotalGb;
  final double? diskFreeGb;
  final int? uptimeS;

  // Relayed from the NAS, which gets them from vps-watch.py. Null when the NAS
  // is off, because they genuinely cannot be measured from inside a container.
  final String? state;

  /// `hostinger` when Hostinger's API said so, `probe` when we inferred it
  /// from the VPS answering us. The UI can be honest about the difference.
  final String? stateFrom;
  final bool? reachable;

  /// Processor time the hypervisor took away. High steal is the signature of
  /// Hostinger throttling the machine.
  final double? stealPct;
  final bool? throttled;
  final List<String> conditions;
  final int? containers;
  final int? running;

  /// How old the relayed figures are. `vps-watch.py` samples every 5 minutes.
  final int? ageS;

  /// True past 15 minutes, so the screen can say the figures are stale rather
  /// than presenting them as current.
  final bool? stale;

  // What Hostinger says the machine *is*, rather than what it is doing. Only
  // populated once something made vps-watch.py call the API, so these are null
  // on a long healthy run — they label the live figures, they are not the
  // reading, and the screen must not wait for them.
  final String? planName;
  final int? vcpus;
  final int? planRamMb;
  final int? planDiskMb;
  final String? hostname;

  /// When the machine renews, and when the domain expires.
  final VpsBilling? billing;

  factory VpsLive.fromJson(Map<String, dynamic> m) => VpsLive(
        cpuPct: _d(m['cpu_pct']),
        cores: _i(m['cores']),
        load1: _d(m['load1']),
        load5: _d(m['load5']),
        load15: _d(m['load15']),
        memPct: _d(m['mem_pct']),
        memTotalGb: _d(m['mem_total_gb']),
        memFreeGb: _d(m['mem_free_gb']),
        diskPct: _d(m['disk_pct']),
        diskTotalGb: _d(m['disk_total_gb']),
        diskFreeGb: _d(m['disk_free_gb']),
        uptimeS: _i(m['uptime_s']),
        state: _s(m['state']),
        stateFrom: _s(m['state_from']),
        reachable: _b(m['reachable']),
        stealPct: _d(m['steal_pct']),
        throttled: _b(m['throttled']),
        conditions: (m['conditions'] is List)
            ? (m['conditions'] as List).whereType<String>().toList()
            : const [],
        containers: _i(m['containers']),
        running: _i(m['running']),
        ageS: _i(m['vps_age_s']),
        stale: _b(m['vps_stale']),
        planName: _s(m['plan_name']),
        vcpus: _i(m['vcpus']),
        planRamMb: _i(m['plan_ram_mb']),
        planDiskMb: _i(m['plan_disk_mb']),
        hostname: _s(m['hostname']),
        billing: m['billing'] is Map
            ? VpsBilling.fromJson(Map<String, dynamic>.from(m['billing'] as Map))
            : null,
      );

  /// Steal above 20% is not a busy neighbour, it is the machine being held
  /// back — the shape of the 15 Aug incident.
  bool get stealIsHigh => (stealPct ?? 0) >= 20;

  bool get containersDegraded {
    final c = containers;
    final r = running;
    if (c == null || r == null) return false;
    return r < c;
  }
}

// ── billing ─────────────────────────────────────────────────────────────────

/// A subscription's next date, and the word it must be said with.
///
/// The verb is carried rather than derived because Hostinger puts the date in
/// one of two mutually exclusive fields depending on auto-renewal, and getting
/// it backwards would tell the owner his server is about to be switched off on
/// the very day it is in fact about to be paid for. `vps-watch.py` resolves it
/// once; nothing downstream, including this class, re-decides it.
@immutable
class VpsSubscription {
  const VpsSubscription({
    this.name,
    this.status,
    this.autoRenew,
    this.dueAt,
    this.dueKind,
    this.daysLeft,
    this.period,
    this.periodUnit,
    this.renewalPrice,
    this.currency,
  });

  final String? name;

  /// Hostinger's own word: `active`, `non_renewing`, `expired`, and so on.
  final String? status;
  final bool? autoRenew;

  /// The resolved date, as an ISO-8601 UTC string.
  final String? dueAt;

  /// `renews` or `expires`. Null when Hostinger gave no date at all, in which
  /// case the screen must say nothing rather than guess.
  final String? dueKind;
  final int? daysLeft;
  final int? period;
  final String? periodUnit;

  /// In minor units, as the API reports it — 209900 is ₹2,099.00.
  final int? renewalPrice;
  final String? currency;

  factory VpsSubscription.fromJson(Map<String, dynamic> m) => VpsSubscription(
        name: _s(m['name']),
        status: _s(m['status']),
        autoRenew: _b(m['auto_renew']),
        dueAt: _s(m['due_at']),
        dueKind: _s(m['due_kind']),
        daysLeft: _i(m['days_left']),
        period: _i(m['period']),
        periodUnit: _s(m['period_unit']),
        renewalPrice: _i(m['renewal_price']),
        currency: _s(m['currency']),
      );

  bool get isExpiring => dueKind == 'expires';
  bool get isRenewing => dueKind == 'renews';

  /// The single word the card leads with. Deliberately not a bare date: "18
  /// Sep" alone is unreadable without knowing which of the two it means.
  String? get verb => switch (dueKind) {
        'renews' => 'Renews',
        'expires' => 'Expires',
        _ => null,
      };

  DateTime? get dueLocal {
    final raw = dueAt;
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// Worth drawing attention to only when something will actually stop. An
  /// auto-renewing subscription 3 days from its billing date is not news; one
  /// that expires in 3 days is the whole screen.
  bool get needsAttention {
    final d = daysLeft;
    if (d == null) return false;
    if (d < 0) return true;
    return isExpiring && d <= 30;
  }

  /// Formatted from minor units. Returns null rather than a bare number, so a
  /// missing currency never renders as an ambiguous "2099".
  String? get priceLabel {
    final p = renewalPrice;
    final c = currency;
    if (p == null || c == null) return null;
    final major = (p / 100).toStringAsFixed(p % 100 == 0 ? 0 : 2);
    final symbol = switch (c.toUpperCase()) {
      'INR' => '\u20B9',
      'USD' => '\u0024',
      'EUR' => '\u20AC',
      'GBP' => '\u00A3',
      _ => '',
    };
    final unit = periodUnit;
    final every = unit == null
        ? ''
        : (period == null || period == 1) ? ' / $unit' : ' / $period ${unit}s';
    return symbol.isEmpty ? '$major $c$every' : '$symbol$major$every';
  }
}

@immutable
class VpsBilling {
  const VpsBilling({
    this.at,
    this.error,
    this.vps,
    this.others = const [],
    this.fromCache = false,
    this.ageS,
  });

  final int? at;
  final String? error;

  /// The subscription for the machine itself.
  final VpsSubscription? vps;

  /// Everything else on the account — today, the domain. Carried because
  /// `monishlabs.com` lapsing would take the site, the cloud and the API down
  /// as completely as the machine stopping, and nothing else watches it.
  final List<VpsSubscription> others;

  /// True when the API is serving a remembered answer because the NAS that
  /// relays it is off. The screen says so rather than implying it is current.
  final bool fromCache;
  final int? ageS;

  factory VpsBilling.fromJson(Map<String, dynamic> m) => VpsBilling(
        at: _i(m['at']),
        error: _s(m['error']),
        vps: m['vps'] is Map
            ? VpsSubscription.fromJson(Map<String, dynamic>.from(m['vps'] as Map))
            : null,
        others: (m['others'] is List)
            ? (m['others'] as List)
                .whereType<Map>()
                .map((e) => VpsSubscription.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
        fromCache: _b(m['from_cache']) ?? false,
        ageS: _i(m['age_s']),
      );

  bool get isEmpty => vps == null && others.isEmpty;
}

// ── the envelope ────────────────────────────────────────────────────────────

@immutable
class NasStatsEnvelope {
  const NasStatsEnvelope({
    required this.online,
    this.reason,
    this.at,
    this.ageS,
    this.lastSeenAt,
    this.snapshot,
    this.vpsLive,
  });

  /// The single switch the dashboard turns on. False means the NAS is off and
  /// the screen goes dull and zeroed — it does NOT mean the request failed.
  final bool online;
  final NasOfflineReason? reason;

  /// When the server built this envelope, in epoch seconds.
  final int? at;

  /// How stale the NAS's own sample is. The daemon serves its last good
  /// sample, so this is what says whether the figures are really moving.
  final int? ageS;

  /// Kept across an outage so the screen can say "last seen 3 minutes ago"
  /// rather than implying it was never there.
  final int? lastSeenAt;

  final NasSnapshot? snapshot;
  final VpsLive? vpsLive;

  factory NasStatsEnvelope.fromJson(Map<String, dynamic> m) {
    final online = _b(m['online']) ?? false;
    final snap = _m(m['snapshot']);
    final vps = _m(m['vps_live']);
    return NasStatsEnvelope(
      online: online,
      reason: online ? null : NasOfflineReason.parse(m['reason']),
      at: _i(m['at']),
      ageS: _i(m['age_s']),
      lastSeenAt: _i(m['last_seen_at']),
      // Trust `online` over the presence of a snapshot, so a server that ever
      // sends both cannot produce a screen that is half live and half dull.
      snapshot: (online && snap != null) ? NasSnapshot.fromJson(snap) : null,
      vpsLive: vps == null ? null : VpsLive.fromJson(vps),
    );
  }

  /// An envelope for before the first response arrives. Renders as the offline
  /// treatment, which is the honest thing to show when nothing is known yet.
  static const NasStatsEnvelope unknown = NasStatsEnvelope(online: false);

  DateTime? get lastSeen => lastSeenAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastSeenAt! * 1000);

  /// True when the NAS is up but its readings have stopped advancing — the
  /// daemon is serving a cached sample and its collector has stalled.
  bool get isStalled => online && (ageS ?? 0) > 30;
}
