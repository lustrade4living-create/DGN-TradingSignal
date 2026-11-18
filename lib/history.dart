// Lich su tin hieu — port spec-web §15 + luu ben (v1.2.3, viec 2).
//
// LUU BEN: moi tin hieu ket thuc (cham TP/SL hoac huy som) deu duoc ghi
// vao file JSON 'signal_history.json' qua AppStorage (MethodChannel
// 'tradesignal/storage', thu muc rieng cua app) va nap lai khi mo app.
// Mo lai app van thay lich su cu. Chi append / ghi de toan bo danh sach
// hien tai — KHONG bao gio tu xoa ban ghi cu khi luu ban moi; chi nut
// "Xoa toan bo lich su" (co xac nhan) moi xoa ca bo nho + file.
//
// Ket qua moi ban ghi suy ra tu realizedR: >= 0 win, < 0 loss, null khi
// dang mo. Win rate / Profit factor hien "—" o UI khi chua co lenh dong.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'safe_json.dart';
import 'storage.dart';

/// pipSize theo spec §3.4 — dung khi khong co ham pip do caller truyen.
double _pipSize(String symbol) {
  switch (symbol) {
    case 'BTCUSD':
      return 1;
    case 'XAUUSD':
      return 0.1;
    case 'USOIL':
    case 'USDJPY':
      return 0.01;
    default:
      return 0.0001;
  }
}

/// 8 cap cua app (spec §2.1) — dung cho thong ke theo cap.
const List<String> histSymbols = <String>[
  'BTCUSD',
  'XAUUSD',
  'EURUSD',
  'GBPUSD',
  'USDCAD',
  'USDCHF',
  'USDJPY',
  'USOIL',
];

/// Ma loai ket qua thoat lenh (5 loai). Dung lam key loc + luu JSON.
const String closeKindSL = 'SL';
const String closeKindTP = 'TP';
const String closeKindEntry = 'ENTRY';
const String closeKindEarlyLoss = 'EARLY_LOSS';
const String closeKindEarlyProfit = 'EARLY_PROFIT';

/// Nhan hien thi tieng Viet cho tung loai ket qua.
const Map<String, String> closeKindLabels = <String, String>{
  closeKindSL: 'SL',
  closeKindTP: 'TP',
  closeKindEntry: 'Thoát tại Entry',
  closeKindEarlyLoss: 'Cắt lỗ sớm',
  closeKindEarlyProfit: 'Cắt lãi sớm',
};

/// Dung sai "thoat dung Entry": 0,05% gia Entry (|gia thoat - Entry|
/// <= 0,0005 x |Entry|). Chon dung sai TUONG DOI theo gia Entry (khong
/// dung 0,1 x ATR) vi don gian, khong phu thuoc ATR luc dong lenh va
/// dong nhat cho ca 8 cap (BTC ~32 USD, vang ~1,9 USD, forex ~0,5 pip).
/// Gia thoat nam trong dung sai nay duoc xem la hoa von, khong tinh
/// lai/lo.
const double entryExitTolerancePct = 0.0005;

/// Phan loai ket qua thoat lenh — ham thuan, test duoc, khong phu thuoc
/// UI hay MethodChannel.
///
/// Thu tu uu tien:
/// 1. Thoat do cham TP/SL: dua vao note/reason ('Cham TP'/'Cham SL')
///    hoac so gia thoat voi SL/TP (cung dung sai 0,05% gia Entry).
/// 2. Thoat som (huy som / dao chieu): so gia thoat voi Entry theo
///    huong BUY/SELL — trong dung sai -> 'ENTRY', lo so voi Entry ->
///    'EARLY_LOSS', lai so voi Entry -> 'EARLY_PROFIT'.
String classifyExit({
  required String action,
  required double entry,
  double? sl,
  double? tp,
  required double exitPrice,
  String note = '',
}) {
  if (note.contains('Chạm TP')) return closeKindTP;
  if (note.contains('Chạm SL')) return closeKindSL;
  final double tol = entry.abs() * entryExitTolerancePct;
  if (tp != null && (exitPrice - tp).abs() <= tol) return closeKindTP;
  if (sl != null && (exitPrice - sl).abs() <= tol) return closeKindSL;
  final double d =
      action == 'BUY' ? exitPrice - entry : entry - exitPrice;
  if (d.abs() <= tol) return closeKindEntry;
  return d < 0 ? closeKindEarlyLoss : closeKindEarlyProfit;
}

class HistEntry {
  final int id;
  final String symbol;
  final String action; // 'BUY' | 'SELL'
  String status; // 'open' | 'closed'
  String note;
  final String strategy; // chien luoc luc mo ('swing'/'volumebs'/'ai')
  final double entry;
  final double? sl;
  final double? tp;
  double? exit;
  final int openAt; // gio mo ban ghi (epoch ms)
  final int startAt; // = closedAt cua tin hieu (gio len tin hieu)
  final int planStop; // = closedAt + 1 gio (gio dung du kien)
  int? exitAt;
  double? realizedR;
  double? exitPips;
  double? exitPct;
  final double conf; // % tin cay luc mo
  final double rr;
  final double atr;
  Map<String, dynamic>? levels; // thang Inv/T1-T4
  Map<String, dynamic>? tiers; // T1-T4 {hit, at, price}
  bool? invHit; // true khi gia da cham Inv (SL)
  double? openPrice; // gia live luc mo (fallback = entry)
  double? simDiff;
  double? simDiffPips;
  double? simDiffPct;
  /// Loai ket qua thoat lenh (1 trong 5 ma o tren); null khi dang mo.
  String? closeKind;

  HistEntry({
    required this.id,
    required this.symbol,
    required this.action,
    this.status = 'open',
    this.note = '',
    required this.strategy,
    required this.entry,
    this.sl,
    this.tp,
    this.exit,
    required this.openAt,
    required this.startAt,
    required this.planStop,
    this.exitAt,
    this.realizedR,
    this.exitPips,
    this.exitPct,
    required this.conf,
    required this.rr,
    required this.atr,
    this.levels,
    this.tiers,
    this.invHit,
    this.openPrice,
    this.simDiff,
    this.simDiffPips,
    this.simDiffPct,
    this.closeKind,
  });

  /// Ket qua suy ra tu realizedR: 'win' (>= 0) / 'loss' (< 0) / null (mo).
  String? get result {
    if (status != 'closed' || realizedR == null) return null;
    return realizedR! >= 0 ? 'win' : 'loss';
  }

  /// Nhan tieng Viet cua loai ket qua; null khi dang mo / chua phan loai.
  String? get closeLabel =>
      closeKind == null ? null : closeKindLabels[closeKind];

  /// Ban ghi day du de luu JSON: cap, huong, gio ra tin hieu (startAt),
  /// Entry/SL/TP, gia thoat, so pip, % lai/lo, loai ket qua, chien luoc,
  /// % tin cay luc ra tin hieu (+ R, ATR, gio mo/dong, ghi chu).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'symbol': symbol,
        'action': action,
        'status': status,
        'note': note,
        'strategy': strategy,
        'entry': entry,
        'sl': sl,
        'tp': tp,
        'exit': exit,
        'openAt': openAt,
        'startAt': startAt,
        'planStop': planStop,
        'exitAt': exitAt,
        'realizedR': realizedR,
        'exitPips': exitPips,
        'exitPct': exitPct,
        'conf': conf,
        'rr': rr,
        'atr': atr,
        'levels': levels,
        'tiers': tiers,
        'invHit': invHit,
        'openPrice': openPrice,
        'simDiff': simDiff,
        'simDiffPips': simDiffPips,
        'simDiffPct': simDiffPct,
        'closeKind': closeKind,
      };

  /// Decode an toan: thieu/sai kieu thi dung mac dinh, KHONG throw.
  /// Tra null neu thieu truong bat buoc (id/symbol/action/entry...).
  static HistEntry? fromJson(Object? v) {
    final Map<String, dynamic>? m = asMap(v);
    if (m == null) return null;
    final int? id = numI(m['id']);
    final double? entry = numD(m['entry']);
    final int? openAt = numI(m['openAt']);
    final int? startAt = numI(m['startAt']);
    final int? planStop = numI(m['planStop']);
    final double? conf = numD(m['conf']);
    final double? rr = numD(m['rr']);
    final double? atr = numD(m['atr']);
    if (id == null ||
        entry == null ||
        openAt == null ||
        startAt == null ||
        planStop == null ||
        conf == null ||
        rr == null ||
        atr == null) {
      return null;
    }
    final String symbol = strOf(m['symbol']);
    final String action = strOf(m['action']);
    if (symbol.isEmpty || action.isEmpty) return null;
    final String kind = strOf(m['closeKind']);
    return HistEntry(
      id: id,
      symbol: symbol,
      action: action,
      status: strOf(m['status'], 'open'),
      note: strOf(m['note']),
      strategy: strOf(m['strategy']),
      entry: entry,
      sl: numD(m['sl']),
      tp: numD(m['tp']),
      exit: numD(m['exit']),
      openAt: openAt,
      startAt: startAt,
      planStop: planStop,
      exitAt: numI(m['exitAt']),
      realizedR: numD(m['realizedR']),
      exitPips: numD(m['exitPips']),
      exitPct: numD(m['exitPct']),
      conf: conf,
      rr: rr,
      atr: atr,
      levels: asMap(m['levels']),
      tiers: asMap(m['tiers']),
      invHit: m['invHit'] is bool ? m['invHit'] as bool : null,
      openPrice: numD(m['openPrice']),
      simDiff: numD(m['simDiff']),
      simDiffPips: numD(m['simDiffPips']),
      simDiffPct: numD(m['simDiffPct']),
      closeKind: closeKindLabels.containsKey(kind) ? kind : null,
    );
  }
}

class SessionHistory extends ChangeNotifier {
  /// File luu lich su tin hieu (rieng biet settings.json).
  static const String persistFile = 'signal_history.json';

  final List<HistEntry> entries = <HistEntry>[];
  int _nextId = 1;
  bool _persistLoaded = false;
  bool _persisting = false;
  bool _persistDirty = false;

  HistEntry? _openOf(String symbol) {
    for (final HistEntry e in entries) {
      if (e.symbol == symbol && e.status == 'open') return e;
    }
    return null;
  }

  double _realizedR(HistEntry e, double exitPrice) {
    if (e.sl == null) return 0;
    final double dist = (e.entry - e.sl!).abs();
    if (dist <= 0) return 0;
    final double d =
        e.action == 'BUY' ? exitPrice - e.entry : e.entry - exitPrice;
    return d / dist;
  }

  void _finishClose(
    HistEntry e, {
    required double exitPrice,
    required int exitAt,
    required String note,
    required double Function(String) pip,
  }) {
    final double pipSize = pip(e.symbol);
    final double d =
        e.action == 'BUY' ? exitPrice - e.entry : e.entry - exitPrice;
    e.exit = exitPrice;
    e.exitAt = exitAt;
    e.status = 'closed';
    e.note = note;
    e.closeKind = classifyExit(
      action: e.action,
      entry: e.entry,
      sl: e.sl,
      tp: e.tp,
      exitPrice: exitPrice,
      note: note,
    );
    e.realizedR = _realizedR(e, exitPrice);
    e.exitPips = pipSize > 0 ? d / pipSize : null;
    e.exitPct = e.entry != 0 ? d / e.entry * 100 : null;
  }

  /// Mo ban ghi moi (unshift len dau danh sach).
  /// - Neu cap dang co lenh mo ma huong DOI thi dong lenh cu truoc bang
  ///   [closeReversal] (gia cat = [livePrice] neu co, khong thi [entry]).
  /// - Neu cap dang co lenh mo CUNG huong thi khong mo trung (bo qua).
  /// - [openPrice]: gia live luc mo; null thi lay [entry] lam moc, luc do
  ///   simDiff = 0 ("khop Entry"). [planStop] tu tinh = startAt + 1 gio.
  void recordOpen({
    required String symbol,
    required String action,
    required double entry,
    double? sl,
    double? tp,
    required double atr,
    required int startAt,
    required String strategy,
    required double conf,
    required double rr,
    Map<String, dynamic>? levels,
    double? openPrice,
    double? livePrice,
  }) {
    final HistEntry? old = _openOf(symbol);
    if (old != null) {
      if (old.action == action) return; // cung huong: khong mo trung
      closeReversal(
        symbol,
        livePrice ?? entry,
        DateTime.now().millisecondsSinceEpoch,
        'Đảo chiều sang $action',
      );
    }
    final double op = openPrice ?? entry;
    final double simDiff = op - entry;
    final double pip = _pipSize(symbol);
    final HistEntry e = HistEntry(
      id: _nextId++,
      symbol: symbol,
      action: action,
      strategy: strategy,
      entry: entry,
      sl: sl,
      tp: tp,
      openAt: DateTime.now().millisecondsSinceEpoch,
      startAt: startAt,
      planStop: startAt + 3600000,
      conf: conf,
      rr: rr,
      atr: atr,
      levels: levels,
      openPrice: op,
      simDiff: simDiff,
      simDiffPips: simDiff / pip,
      simDiffPct: entry != 0 ? simDiff / entry * 100 : null,
    );
    entries.insert(0, e);
    notifyListeners();
  }

  /// Kiem tra gia live moi lan goi (web: moi 3 giay — spec §15.2):
  /// BUY cham TP khi price >= TP (dong tai TP, note "Chạm TP"), cham SL
  /// khi price <= SL (note "Chạm SL"); SELL nguoc lai.
  /// Khi dong do cham TP: ghi tiers T4 da cham (neu co tiers).
  /// Khi dong do cham SL: ghi invHit = true.
  /// Moi lenh dong o day deu duoc luu ben ngay (xem [_schedulePersist]).
  void checkOutcomes(Map<String, double> livePrices, double Function(String) pip) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;
    for (final HistEntry e in List<HistEntry>.of(entries)) {
      if (e.status != 'open') continue;
      final double? price = livePrices[e.symbol];
      if (price == null || e.sl == null || e.tp == null) continue;
      if (e.action == 'BUY') {
        if (price >= e.tp!) {
          _finishClose(e,
              exitPrice: e.tp!, exitAt: now, note: 'Chạm TP', pip: pip);
          if (e.tiers != null) {
            e.tiers!['T4'] = <String, dynamic>{
              'hit': true,
              'at': now,
              'price': e.tp,
            };
          }
          changed = true;
        } else if (price <= e.sl!) {
          _finishClose(e,
              exitPrice: e.sl!, exitAt: now, note: 'Chạm SL', pip: pip);
          e.invHit = true;
          changed = true;
        }
      } else {
        if (price <= e.tp!) {
          _finishClose(e,
              exitPrice: e.tp!, exitAt: now, note: 'Chạm TP', pip: pip);
          if (e.tiers != null) {
            e.tiers!['T4'] = <String, dynamic>{
              'hit': true,
              'at': now,
              'price': e.tp,
            };
          }
          changed = true;
        } else if (price >= e.sl!) {
          _finishClose(e,
              exitPrice: e.sl!, exitAt: now, note: 'Chạm SL', pip: pip);
          e.invHit = true;
          changed = true;
        }
      }
    }
    if (changed) {
      _schedulePersist();
      notifyListeners();
    }
  }

  /// Dong lenh mo cua cap khi dao chieu (huy som).
  /// [reason] vd: 'Đảo chiều sang SELL'. Note ghi day du gia cat + pip/%:
  /// "Đảo chiều sang SELL — HỦY LỆNH SỚM, cắt tại giá ... · +/−X,X pip
  /// (+/−X,XX% so với Entry ...; SL gốc ...)".
  /// Lenh dong o day duoc luu ben ngay (xem [_schedulePersist]).
  void closeReversal(String symbol, double exitPrice, int exitAt, String reason) {
    final HistEntry? e = _openOf(symbol);
    if (e == null) return;
    final double d =
        e.action == 'BUY' ? exitPrice - e.entry : e.entry - exitPrice;
    final double pip = _pipSize(symbol);
    final double pips = d / pip;
    final double pct = e.entry != 0 ? d / e.entry * 100 : 0;
    final String pipsTxt =
        '${pips >= 0 ? '+' : ''}${pips.toStringAsFixed(1)}';
    final String pctTxt =
        '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}';
    final String slTxt =
        e.sl != null ? e.sl!.toStringAsFixed(2) : '—';
    final String note =
        '$reason — HỦY LỆNH SỚM, cắt tại giá $exitPrice · $pipsTxt pip '
        '($pctTxt% so với Entry ${e.entry}; SL gốc $slTxt)';
    _finishClose(e,
        exitPrice: exitPrice,
        exitAt: exitAt,
        note: note,
        pip: (String _) => pip);
    _schedulePersist();
    notifyListeners();
  }

  /// Cap nhat trang thai tang (thang TP) cho lenh mo cua cap — de module
  /// thang TP ghi vao. [invHit] = true khi gia da cham Inv (SL).
  void updateTiers(String symbol, Map<String, dynamic> tiers, bool? invHit) {
    final HistEntry? e = _openOf(symbol);
    if (e == null) return;
    e.tiers = tiers;
    e.invHit = invHit;
    notifyListeners();
  }

  // --- Luu ben (signal_history.json) ---------------------------------------
  //
  /// Toan bo danh sach hien tai duoi dang JSON de luu. Luu lai TOAN BO
  /// danh sach (khong chi ban ghi moi) nen khong bao gio lam mat ban ghi
  /// cu; ban ghi moi chi duoc them vao danh sach truoc khi luu.
  Map<String, dynamic> toPersistJson() => <String, dynamic>{
        'version': 1,
        'entries': entries.map((HistEntry e) => e.toJson()).toList(),
      };

  /// Giai ma JSON da luu thanh danh sach ban ghi (bo qua ban ghi loi,
  /// KHONG throw). Dung chung cho [loadPersisted] va test.
  static List<HistEntry> entriesFromPersistJson(Map<String, dynamic>? json) {
    if (json == null) return <HistEntry>[];
    final List<dynamic>? raw = asList(json['entries']);
    if (raw == null) return <HistEntry>[];
    final List<HistEntry> out = <HistEntry>[];
    final Set<int> seenIds = <int>{};
    for (final Object? item in raw) {
      final HistEntry? e = HistEntry.fromJson(item);
      // Chong ghi trung 1 tin hieu 2 lan: bo qua id da co.
      if (e != null && seenIds.add(e.id)) out.add(e);
    }
    return out;
  }

  /// Luu ngay danh sach hien tai ra file. Tra false (khong throw) khi
  /// thiet bi chua ho tro luu — app van chay tiep.
  Future<bool> persist() async {
    return AppStorage.saveJson(toPersistJson(), file: persistFile);
  }

  /// Gom cac lan luu lien tiep (vd nhieu lenh dong cung 1 nhip 3 giay)
  /// thanh 1 lan ghi file; neu dang ghi thi ghi lai 1 lan nua sau do.
  void _schedulePersist() {
    if (_persisting) {
      _persistDirty = true;
      return;
    }
    _persisting = true;
    unawaited(persist().then((_) {
      _persisting = false;
      if (_persistDirty) {
        _persistDirty = false;
        _schedulePersist();
      }
    }));
  }

  /// Nap lich su da luu (goi 1 lan khi khoi dong). Tra false khi khong co
  /// file / file loi (danh sach giu nguyen, app chay tiep). Goi lai chi
  /// nap lai khi [force] = true.
  Future<bool> loadPersisted({bool force = false}) async {
    if (_persistLoaded && !force) return true;
    final Map<String, dynamic>? json =
        await AppStorage.loadJson(file: persistFile);
    if (json == null) {
      _persistLoaded = true;
      return false;
    }
    final List<HistEntry> loaded = entriesFromPersistJson(json);
    entries
      ..clear()
      ..addAll(loaded);
    int maxId = 0;
    for (final HistEntry e in loaded) {
      if (e.id > maxId) maxId = e.id;
    }
    _nextId = maxId + 1;
    _persistLoaded = true;
    notifyListeners();
    return true;
  }

  /// Nap neu chua nap (dung o HistoryTab mo lan dau). An toan khi goi
  /// nhieu lan.
  Future<bool> ensureLoaded() => loadPersisted();

  /// Xoa TOAN BO lich su: ca bo nho lan file da luu (ghi de file bang
  /// danh sach rong — plugin luu tru chi co load/save, khong co delete).
  Future<bool> clearAllPersisted() async {
    entries.clear();
    _nextId = 1;
    _persistLoaded = true;
    final bool ok = await AppStorage.saveJson(
      <String, dynamic>{'version': 1, 'entries': <dynamic>[]},
      file: persistFile,
    );
    notifyListeners();
    return ok;
  }

  // --- Thong ke phien (chi tinh lenh DA DONG) ---
  List<HistEntry> get _closed =>
      entries.where((HistEntry e) => e.status == 'closed').toList();

  /// Chi cac ban ghi da dong (moi nhat len tren — thu tu cua [entries]).
  List<HistEntry> get closedEntries => _closed;

  int get closedCount => _closed.length;
  int get openCount =>
      entries.where((HistEntry e) => e.status == 'open').length;
  int get wins => _closed
      .where((HistEntry e) => e.realizedR != null && e.realizedR! >= 0)
      .length;
  int get losses => _closed
      .where((HistEntry e) => e.realizedR != null && e.realizedR! < 0)
      .length;

  /// So luong tung loai ket qua thoat lenh (chi lenh da dong).
  /// Luon du ca 5 khoa, gia tri 0 khi chua co.
  Map<String, int> get closeKindCounts {
    final Map<String, int> out = <String, int>{
      closeKindSL: 0,
      closeKindTP: 0,
      closeKindEntry: 0,
      closeKindEarlyLoss: 0,
      closeKindEarlyProfit: 0,
    };
    for (final HistEntry e in _closed) {
      final String? k = e.closeKind;
      if (k != null && out.containsKey(k)) out[k] = out[k]! + 1;
    }
    return out;
  }

  List<double> get _closedR => _closed
      .where((HistEntry e) => e.realizedR != null)
      .map((HistEntry e) => e.realizedR!)
      .toList();

  /// Win rate %; null khi chua co lenh dong (UI hien "—").
  double? get winRate =>
      closedCount > 0 ? wins / closedCount * 100 : null;

  /// Profit factor; null khi khong tinh duoc (khong co R thang -> UI "—";
  /// khong co lenh thua ma co R thang -> double.infinity, UI hien "∞").
  double? get profitFactor {
    final List<double> rs = _closedR;
    if (rs.isEmpty) return null;
    double sumWin = 0;
    double sumLossAbs = 0;
    for (final double r in rs) {
      if (r >= 0) {
        sumWin += r;
      } else {
        sumLossAbs += r.abs();
      }
    }
    if (sumWin <= 0) return null;
    if (sumLossAbs <= 0) return double.infinity;
    return sumWin / sumLossAbs;
  }

  /// RR thuc te TB = R thang TB / |R thua TB|; null khi thieu mot phia.
  double? get avgRealRr {
    final List<double> rs = _closedR;
    final List<double> w =
        rs.where((double r) => r >= 0).toList();
    final List<double> l = rs.where((double r) => r < 0).toList();
    if (w.isEmpty || l.isEmpty) return null;
    final double avgW = w.reduce((a, b) => a + b) / w.length;
    final double avgL =
        l.map((double r) => r.abs()).reduce((a, b) => a + b) / l.length;
    return avgL > 0 ? avgW / avgL : null;
  }

  /// R trung binh / lenh dong; null khi chua co lenh dong co R.
  double? get avgR {
    final List<double> rs = _closedR;
    if (rs.isEmpty) return null;
    return rs.reduce((a, b) => a + b) / rs.length;
  }

  /// Tong R; null khi chua co lenh dong co R.
  double? get totalR {
    final List<double> rs = _closedR;
    if (rs.isEmpty) return null;
    return rs.reduce((a, b) => a + b);
  }

  /// Thong ke theo tung cap trong 8 cap (spec §15.3).
  Map<String, ({int wins, int losses, double? winRate, double? profitFactor, double? avgR, double? totalR})> statsByPair() {
    final Map<String, ({int wins, int losses, double? winRate, double? profitFactor, double? avgR, double? totalR})> out =
        <String, ({int wins, int losses, double? winRate, double? profitFactor, double? avgR, double? totalR})>{};
    for (final String sym in histSymbols) {
      final List<HistEntry> closed = _closed
          .where((HistEntry e) => e.symbol == sym)
          .toList();
      final List<double> rs = closed
          .where((HistEntry e) => e.realizedR != null)
          .map((HistEntry e) => e.realizedR!)
          .toList();
      final int w = closed
          .where((HistEntry e) => e.realizedR != null && e.realizedR! >= 0)
          .length;
      final int l = closed
          .where((HistEntry e) => e.realizedR != null && e.realizedR! < 0)
          .length;
      double? pf;
      double? wr;
      double? ar;
      double? tr;
      if (closed.isNotEmpty) {
        wr = w / closed.length * 100;
      }
      if (rs.isNotEmpty) {
        double sumWin = 0;
        double sumLossAbs = 0;
        for (final double r in rs) {
          if (r >= 0) {
            sumWin += r;
          } else {
            sumLossAbs += r.abs();
          }
        }
        if (sumWin > 0) {
          pf = sumLossAbs <= 0 ? double.infinity : sumWin / sumLossAbs;
        }
        tr = rs.reduce((a, b) => a + b);
        ar = tr / rs.length;
      }
      out[sym] = (
        wins: w,
        losses: l,
        winRate: wr,
        profitFactor: pf,
        avgR: ar,
        totalR: tr,
      );
    }
    return out;
  }

  /// Loc danh sach. [result]: 'all' (mac dinh) / 'open' / 'win' / 'loss'
  /// / 'SL' / 'TP' / 'ENTRY' / 'EARLY_LOSS' / 'EARLY_PROFIT' (5 loai
  /// ket qua thoat lenh — chi ban ghi da dong).
  /// [todayOnly]: chi ban ghi mo trong ngay hom nay (gio dia phuong).
  List<HistEntry> filter({String? symbol, bool? todayOnly, String? result}) {
    Iterable<HistEntry> list = entries;
    if (symbol != null && symbol != 'Tất cả') {
      list = list.where((HistEntry e) => e.symbol == symbol);
    }
    if (todayOnly == true) {
      final DateTime now = DateTime.now();
      final int startOfDay =
          DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      list = list.where((HistEntry e) => e.openAt >= startOfDay);
    }
    switch (result) {
      case 'open':
        list = list.where((HistEntry e) => e.status == 'open');
      case 'win':
        list = list.where((HistEntry e) => e.result == 'win');
      case 'loss':
        list = list.where((HistEntry e) => e.result == 'loss');
      case closeKindSL:
      case closeKindTP:
      case closeKindEntry:
      case closeKindEarlyLoss:
      case closeKindEarlyProfit:
        list = list.where((HistEntry e) => e.closeKind == result);
      case 'all':
      case null:
        break;
      default:
        break;
    }
    return list.toList();
  }
}
