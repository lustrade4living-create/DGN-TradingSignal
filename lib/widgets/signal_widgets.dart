// Widget tín hiệu dùng chung: thẻ tín hiệu, dải ngang, bảng điểm,
// điểm vào tối ưu, Trend, thang TP, Price Action, mẫu hình, cảnh báo.
import 'package:flutter/material.dart';

import '../alerts.dart';
import '../app_theme.dart';
import '../engine.dart';
import '../gauge_ladder.dart';
import '../indicators.dart' as ind;
import '../patterns.dart';
import '../signal_core.dart';
import '../signal_status.dart';
import 'gauge_widget.dart';

String fmtPips(double pips) =>
    '${pips >= 0 ? '+' : ''}${pips.toStringAsFixed(1).replaceAll('.', ',')}';

String fmtPct2(double v) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2).replaceAll('.', ',')}%';

/// Màu chip theo trạng thái vào lệnh (xem lib/signal_status.dart).
Color signalStatusColor(SignalStatus status) => switch (status) {
      SignalStatus.now => AppColors.up,
      SignalStatus.limit => AppColors.gold,
      SignalStatus.expired => AppColors.dn,
      SignalStatus.wait => AppColors.mut2,
      SignalStatus.unknown => AppColors.mut2,
    };

/// Hàng trạng thái vào lệnh: chip trạng thái + khoảng cách giá live tới
/// Entry (pip/%) + giờ ra tín hiệu / giờ hết hiệu lực + đồng hồ còn lại.
///
/// Đồng hồ "Còn MM:SS" nhích từng giây nhờ nhịp tick() 1 giây của engine
/// (trang chủ bọc ListenableBuilder trên engine, tick() gọi
/// notifyListeners() mỗi giây) — widget này KHÔNG tạo timer riêng.
/// Giá live bản thân polling 2 giây nên giá hiển thị theo nhịp 2 giây,
/// còn trạng thái và thời gian còn lại vẫn nhích từng giây.
class SignalStatusRow extends StatelessWidget {
  const SignalStatusRow({
    super.key,
    required this.status,
    required this.symbol,
    required this.issuedAtMs,
    required this.expiryAtMs,
    this.compact = false,
  });

  final SignalStatusResult status;
  final String symbol;
  final int issuedAtMs;
  final int expiryAtMs;

  /// Bản gọn (dải ngang): chỉ chip + khoảng cách, không có giờ/lý do.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color c = signalStatusColor(status.status);
    final String distTxt = status.distPips == null || status.distPct == null
        ? 'Chưa có giá live để đo khoảng cách tới Entry'
        : 'Cách Entry: ${fmtPips(status.distPips!)} pip '
            '(${fmtPct2(status.distPct!)})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c),
              ),
              child: Text(
                status.label,
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            if (status.betterThanEntry)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.up.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.up),
                ),
                child: const Text(
                  'giá tốt hơn Entry',
                  style: TextStyle(
                    color: AppColors.up,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            if (!compact)
              Text(
                'Còn ${formatRemaining(status.remainingMs)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: status.status == SignalStatus.expired
                      ? AppColors.dn
                      : AppColors.txt,
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          compact
              ? distTxt
              : '$distTxt · Ra lúc ${vnTimeStr(issuedAtMs)} · '
                  'Hết hiệu lực ${vnTimeStr(expiryAtMs)}'
                  '${status.tp1FromFallback ? ' · TP1 = Entry ±1×ATR' : ''}',
          style: const TextStyle(fontSize: 12, color: AppColors.mut),
        ),
        if (!compact) ...[
          const SizedBox(height: 2),
          Text(
            status.reason,
            style: const TextStyle(fontSize: 12, color: AppColors.mut),
          ),
        ],
      ],
    );
  }
}

/// Thẻ tín hiệu 1 cặp (dùng ở đầu tab Tín hiệu + thẻ nổi bật dùng bản riêng).
class SignalCard extends StatelessWidget {
  const SignalCard({
    super.key,
    required this.engine,
    required this.signal,
    this.isStrongest = false,
    this.onTap,
    this.showInvalidation = true,
    this.compactStatus = false,
  });

  final MockEngine engine;
  final StaticSignal signal;
  final bool isStrongest;
  final VoidCallback? onTap;
  final bool showInvalidation;

  /// Bản gọn của hàng trạng thái (dùng trong dải ngang SignalRail).
  final bool compactStatus;

  @override
  Widget build(BuildContext context) {
    final double? live = engine.prices[signal.symbol];
    final double? liveVsEntry = live == null
        ? null
        : (live - signal.entry) / signal.entry * 100;
    final Invalidation? inv =
        showInvalidation ? engine.lastInvalidations[signal.symbol] : null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isStrongest ? AppColors.gold : AppColors.line,
          width: isStrongest ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        signal.symbol,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isStrongest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.gold),
                          ),
                          child: const Text(
                            '★ NỔI BẬT',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  actionBadge(signal.action),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _kvMini('Entry', engine.fmt(signal.entry, signal.symbol)),
                  ),
                  Expanded(
                    child: _kvMini(
                      'SL',
                      signal.sl == null
                          ? '—'
                          : engine.fmt(signal.sl!, signal.symbol),
                      color: AppColors.dn,
                    ),
                  ),
                  Expanded(
                    child: _kvMini(
                      'TP',
                      signal.tp == null
                          ? '—'
                          : engine.fmt(signal.tp!, signal.symbol),
                      color: AppColors.up,
                    ),
                  ),
                  Expanded(
                    child: _kvMini('RR', '1 : ${signal.rr.toStringAsFixed(1)}'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tin cậy ${signal.conf}%  ·  Gốc ${signal.baseConf} · Trend ${signal.trendIndex} · PA ${signal.paIndex}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.mut),
                    ),
                  ),
                  if (liveVsEntry != null)
                    Text(
                      'Giá live ${liveVsEntry >= 0 ? '+' : ''}${liveVsEntry.toStringAsFixed(2).replaceAll('.', ',')}% so với Entry',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: liveVsEntry >= 0 ? AppColors.up : AppColors.dn,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SignalStatusRow(
                status: classifyStaticSignal(
                  signal,
                  livePrice: live,
                  nowMs: DateTime.now().millisecondsSinceEpoch,
                ),
                symbol: signal.symbol,
                issuedAtMs: signal.closedAt,
                expiryAtMs: signalExpiryMs(signal.closedAt),
                compact: compactStatus,
              ),
              const SizedBox(height: 4),
              Text(
                sigStopInfo(signal),
                style: const TextStyle(fontSize: 12, color: AppColors.mut),
              ),
              if (signal.optimal != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Điểm vào tối ưu: ${engine.fmt(signal.optimal!.price, signal.symbol)} · ${signal.optimal!.quality} ${'★' * signal.optimal!.stars}${'☆' * (3 - signal.optimal!.stars)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.mut),
                ),
              ],
              if (signal.reasons.isNotEmpty) ...[
                const SizedBox(height: 4),
                ...signal.reasons.take(2).map(
                      (r) => Text('• $r',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.mut)),
                    ),
              ],
              if (inv != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.dn.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.dn.withOpacity(0.4)),
                  ),
                  child: Text(
                    'Lệnh trước hủy sớm: ${inv.oldAction} · cắt tại ${engine.fmt(inv.exit, inv.symbol)} · ${fmtPips(inv.pips)} pip (${fmtPct2(inv.pct)})',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.dn),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _kvMini(String k, String v, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 11, color: AppColors.mut2)),
        Text(
          v,
          style: TextStyle(
              fontWeight: FontWeight.bold, color: color ?? AppColors.txt),
        ),
      ],
    );
  }
}

/// Dải tín hiệu ngang (Trang chủ + Chiến lược AI): thẻ 248px cuộn ngang,
/// BUY/SELL trước theo confidence giảm dần, WAIT sau.
class SignalRail extends StatelessWidget {
  const SignalRail({
    super.key,
    required this.engine,
    required this.onSelect,
  });

  final MockEngine engine;
  final void Function(String symbol) onSelect;

  @override
  Widget build(BuildContext context) {
    final List<StaticSignal> all = engine.staticSignals.values
        .whereType<StaticSignal>()
        .toList();
    if (all.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Đang quét 8 cặp… (chờ tải đủ nến H1, cần ≥ 55 nến đã đóng)'),
        ),
      );
    }
    final List<StaticSignal> sorted = List<StaticSignal>.of(all)
      ..sort((a, b) {
        final int rankA = a.action == 'WAIT' ? 1 : 0;
        final int rankB = b.action == 'WAIT' ? 1 : 0;
        if (rankA != rankB) return rankA - rankB;
        return b.conf.compareTo(a.conf);
      });
    final StaticSignal? strongest = all
        .where((s) => s.action != 'WAIT')
        .fold<StaticSignal?>(null, (prev, s) =>
            prev == null || s.conf > prev.conf ? s : prev);
    return SizedBox(
      height: 208,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        itemBuilder: (context, i) {
          final StaticSignal s = sorted[i];
          final bool star = strongest != null &&
              identical(s, strongest);
          return Container(
            width: 248,
            margin: EdgeInsets.only(right: 10, left: i == 0 ? 0 : 0),
            child: SignalCard(
              engine: engine,
              signal: s,
              isStrongest: star,
              showInvalidation: false,
              compactStatus: true,
              onTap: () => onSelect(s.symbol),
            ),
          );
        },
      ),
    );
  }
}

/// Bảng phân tích điểm 50/25/25 (spec §4.5).
class ScoreTable extends StatelessWidget {
  const ScoreTable({super.key, required this.signal});

  final StaticSignal signal;

  @override
  Widget build(BuildContext context) {
    Widget row(String name, String desc, int score, double weight,
        double contrib) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text('$score% · ${(weight * 100).toInt()}% · +${contrib.toStringAsFixed(1)}',
                    style: const TextStyle(color: AppColors.mut)),
              ],
            ),
            Text(desc,
                style: const TextStyle(fontSize: 12, color: AppColors.mut)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 7,
                backgroundColor: AppColors.line,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.gold),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(
          'Tín hiệu gốc',
          'EMA20/50 H1 · RSI(14) M15 · ATR(14)',
          signal.baseConf,
          0.50,
          signal.baseConf * 0.5,
        ),
        row(
          'Trend đa khung',
          '${signal.trendAligned}/${signal.trendAvail} khung cùng chiều (M5·M15·H1·H4·D1)',
          signal.trendIndex,
          0.25,
          signal.trendIndex * 0.25,
        ),
        row(
          'Price Action',
          '${signal.paAligned} mẫu cùng chiều · ${signal.paOpposed} ngược · ${signal.paTotal} mẫu (Cơ bản + Nâng cao)',
          signal.paIndex,
          0.25,
          signal.paIndex * 0.25,
        ),
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TỔNG ĐỘ TIN CẬY${signal.action == 'WAIT' ? ' (WAIT — trần 62%)' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${signal.conf}%',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.blue,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Hộp "Điểm vào chuẩn & đẹp — tối ưu" (spec §5.3).
class OptimalBox extends StatelessWidget {
  const OptimalBox({super.key, required this.engine, required this.signal});

  final MockEngine engine;
  final StaticSignal signal;

  @override
  Widget build(BuildContext context) {
    final OptimalEntry? o = signal.optimal;
    if (o == null) return const Text('Chưa có điểm vào tối ưu.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                o.label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '${'★' * o.stars}${'☆' * (3 - o.stars)}',
              style: const TextStyle(color: AppColors.gold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Điểm vào: ${engine.fmt(o.price, signal.symbol)}'),
        Text(
            'Vùng vào: ${engine.fmt(o.zoneLow, signal.symbol)} – ${engine.fmt(o.zoneHigh, signal.symbol)}'),
        Text(
            'Chất lượng: ${o.quality}${o.isFallback ? ' (vùng tham chiếu, chưa nên vào tại đây)' : ''}'),
        if (signal.sl != null && signal.tp != null)
          Text(
              'RR tại điểm tối ưu ≈ 1 : ${o.rrOptimal.toStringAsFixed(1)} (tại Entry chính 1 : ${signal.rr.toStringAsFixed(1)})'),
        const SizedBox(height: 4),
        const Text(
          'Điểm tối ưu không thay Entry/SL/TP tĩnh — chỉ là điểm chờ vào tốt hơn.',
          style: TextStyle(fontSize: 12, color: AppColors.mut),
        ),
      ],
    );
  }
}

/// Trend đa khung dạng pill + gauge.
class TrendGaugeBlock extends StatelessWidget {
  const TrendGaugeBlock({super.key, required this.engine, required this.symbol});

  final MockEngine engine;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final Map<String, TrendInfo> trends = engine.trendsFor(symbol);
    final GaugeData gauge = gaugeFromTrends(trends);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: ['M5', 'M15', 'H1', 'H4', 'D1'].map((tf) {
            final TrendInfo? t = trends[tf];
            if (t == null || !t.enough) {
              return Chip(label: Text('$tf · Đang tải…'));
            }
            final String dirTxt =
                t.dir == 'up' ? '▲ Tăng' : t.dir == 'dn' ? '▼ Giảm' : '◆ Ngang';
            final Color c = t.dir == 'up'
                ? AppColors.up
                : t.dir == 'dn'
                    ? AppColors.dn
                    : AppColors.mut2;
            return Chip(
              label: Text(
                '$tf $dirTxt${t.rsi9 != null ? ' · RSI9 ${t.rsi9!.toStringAsFixed(0)}' : ''}',
                style: TextStyle(color: c, fontWeight: FontWeight.bold),
              ),
              side: BorderSide(color: c),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        GaugeWidget(gauge: gauge),
      ],
    );
  }
}

/// Thang TP Inv/T1–T4 (spec §8), sắp xếp giá giảm dần.
class LadderView extends StatelessWidget {
  const LadderView({
    super.key,
    required this.engine,
    required this.signal,
  });

  final MockEngine engine;
  final StaticSignal signal;

  @override
  Widget build(BuildContext context) {
    final LadderLevels? lv = signal.levels;
    if (lv == null) {
      return const Text('Chưa có thang TP (tín hiệu WAIT hoặc thiếu SL/TP).');
    }
    final double pip = ind.pipSize(signal.symbol);
    final double? live = engine.prices[signal.symbol];
    final Map<String, double> rows = <String, double>{
      'T4': lv.t4,
      'T3': lv.t3,
      'T2': lv.t2,
      'T1': lv.t1,
      'Entry': lv.entry,
      'Inv (SL)': lv.inv,
    };
    final List<MapEntry<String, double>> sorted = rows.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final Map<String, TierStatus>? tiers =
        engine.tierStatusFor(signal.symbol);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (live != null)
          Text(
            'Chênh mở phòng: giá live ${engine.fmt(live, signal.symbol)} so với Entry ${engine.fmt(lv.entry, signal.symbol)}',
            style: const TextStyle(fontSize: 12, color: AppColors.mut),
          ),
        const SizedBox(height: 6),
        ...sorted.map((e) {
          final bool isEntry = e.key == 'Entry';
          final bool isInv = e.key.startsWith('Inv');
          final String tierKey =
              isEntry ? 'Entry' : isInv ? 'Inv' : e.key;
          final TierStatus? st = tiers?[tierKey];
          final double distPips = (e.value - lv.entry).abs() / pip;
          final double distPct = lv.entry != 0
              ? (e.value - lv.entry).abs() / lv.entry * 100
              : 0;
          final Color c = isEntry
              ? AppColors.mut2
              : isInv
                  ? AppColors.dn
                  : AppColors.up;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    e.key,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: c),
                  ),
                ),
                Expanded(
                  child: Text(
                    engine.fmt(e.value, signal.symbol),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!isEntry)
                  Text(
                    '${distPips >= 0 ? '+' : ''}${distPips.toStringAsFixed(1).replaceAll('.', ',')} pip · ${distPct.toStringAsFixed(2).replaceAll('.', ',')}% từ Entry',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.mut),
                  ),
                if (st != null && st.hit)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('✓ đã chạm',
                        style: TextStyle(
                            color: AppColors.up,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        ...['T1', 'T2', 'T3', 'T4', 'Inv'].map((k) {
          final String note = engine.tierNoteFor(signal.symbol, k);
          if (note.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(note,
                style: const TextStyle(fontSize: 12, color: AppColors.mut)),
          );
        }),
      ],
    );
  }
}

/// Tóm tắt Price Action 2 mức (spec §5).
class PaSummary extends StatelessWidget {
  const PaSummary({super.key, required this.engine, required this.symbol});

  final MockEngine engine;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final PaResult pa = engine.paFor(symbol);
    if (pa.total == 0) {
      return const Text(
          'Chưa đủ nến M15 (cần ≥ 25 nến đã đóng) để tính Price Action.');
    }
    Widget group(String title, List<PaPattern> list) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ...list.map((p) {
            final String dirTxt = p.dir == 'bull'
                ? '▲ Tăng'
                : p.dir == 'bear'
                    ? '▼ Giảm'
                    : '— Trung tính';
            final Color c = p.dir == 'bull'
                ? AppColors.up
                : p.dir == 'bear'
                    ? AppColors.dn
                    : AppColors.mut2;
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(p.name),
                  Text(dirTxt,
                      style: TextStyle(color: c, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
        ],
      );
    }

    final StaticSignal? sg = engine.staticSignals[symbol];
    final bool wantUp = sg == null
        ? true
        : sg.action == 'SELL'
            ? false
            : true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Điểm PA: ${pa.index(wantUp)} · ${wantUp ? pa.bull : pa.bear} mẫu cùng chiều · ${wantUp ? pa.bear : pa.bull} ngược · ${pa.total} mẫu',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        group('Cơ bản (5 mẫu — nến M15 đóng gần nhất)', pa.basic),
        const SizedBox(height: 8),
        group('Nâng cao (7 mẫu)', pa.advanced),
      ],
    );
  }
}

/// Thư viện mẫu hình nến — top 6 mẫu có số lần > 0 (spec §6).
class PatternList extends StatelessWidget {
  const PatternList({super.key, required this.engine, required this.symbol});

  final MockEngine engine;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final List<PatternStat> all =
        engine.patternsFor(symbol, engine.timeframe);
    if (all.isEmpty || all.every((p) => p.count == 0) && all.length < 30) {
      // countPatterns trả đủ 15 mẫu ngay cả khi chưa đủ nến (windowLen nhỏ);
      // kiểm tra windowLen để báo chưa đủ nến.
      final int win = all.isNotEmpty ? all.first.windowLen : 0;
      if (win < 30) {
        return const Text(
            'Chưa đủ nến (cần ≥ 30 nến đã đóng) — không hiện số thay thế.');
      }
    }
    final List<PatternStat> top = topPatterns(all, n: 6);
    if (top.isEmpty) {
      return const Text('Chưa có mẫu hình nào xuất hiện trong 200 nến gần nhất.');
    }
    return Column(
      children: top.map((p) {
        final String dirTxt = switch (p.dir) {
          'bull' || 'reversal-up' => 'Đảo chiều tăng',
          'bear' || 'reversal-down' => 'Đảo chiều giảm',
          'neutral' => 'Trung tính',
          _ => 'Trung tính',
        };
        final Color c = p.dir.contains('up')
            ? AppColors.up
            : p.dir.contains('down')
                ? AppColors.dn
                : AppColors.mut2;
        return Card(
          color: p.fresh ? AppColors.gold.withOpacity(0.08) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: p.fresh ? AppColors.gold : AppColors.line,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.nameVn} (${p.nameEn})${p.fresh ? ' · Vừa xuất hiện' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        p.lastTime == null
                            ? 'Chưa xuất hiện'
                            : 'Lần gần nhất: ${vnDateStr(p.lastTime!)}${p.fresh ? ' — chính là nến đóng gần nhất' : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.mut),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${p.count} lần',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(dirTxt,
                    style: TextStyle(
                        color: c, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Cảnh báo Xung/TURN (spec §9).
class AlertsView extends StatelessWidget {
  const AlertsView({super.key, required this.engine});

  final MockEngine engine;

  @override
  Widget build(BuildContext context) {
    final List<AlertItem> items = engine.alerts.visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (engine.alerts.latestBanner != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold),
            ),
            child: Row(
              children: [
                Expanded(child: Text(engine.alerts.latestBanner!)),
                TextButton(
                  onPressed: engine.alerts.clearBanner,
                  child: const Text('Ẩn'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Chip(label: Text('${engine.alerts.items.length} cảnh báo')),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('Chưa có cảnh báo nào trong phiên này…',
              style: TextStyle(color: AppColors.mut)),
        ...items.map((a) {
          final bool isXung = a.kind == 'XUNG';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isXung ? AppColors.blue : AppColors.gold)
                              .withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isXung ? 'XUNG ĐA KHUNG' : 'TURN ĐỒNG BỘ',
                          style: TextStyle(
                            color: isXung ? AppColors.blue : AppColors.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(a.symbol,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text(vnDateStr(a.time),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.mut)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(a.text),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Khối "Quy tắc Swing đang áp dụng" (tóm tắt §3–§8 của web).
class SwingRulesCard extends StatelessWidget {
  const SwingRulesCard({super.key});

  @override
  Widget build(BuildContext context) {
    const List<String> rules = <String>[
      'Entry = giá đóng nến H1 đã đóng gần nhất; SL/TP chốt cứng lúc nến H1 đóng, không đổi theo giá live.',
      'SL = Entry ∓ hệ số SL × ATR(H1); TP = Entry ± hệ số TP × ATR(H1); RR = hệ số TP / hệ số SL (mặc định 1 : 2,0).',
      'Tín hiệu chỉ tính lại khi có nến H1 mới đóng hoặc khi đổi chiến lược/thông số (force).',
      'Độ tin cậy = 50% tín hiệu gốc + 25% Trend đa khung + 25% Price Action; WAIT trần 62%, clamp 5–97.',
      'Đảo chiều (BUY/SELL → WAIT hoặc sang hướng ngược) thì hủy lệnh sớm, ghi rõ giá cắt + pip/% .',
      'Thang TP: Inv (SL) · T1 25% · T2 50% · T3 75% · T4 = TP; theo dõi từng tầng bằng nến M5/M15 + giá live.',
      'Điểm vào tối ưu chỉ là điểm chờ vào tốt hơn, không thay Entry/SL/TP tĩnh.',
      'Trạng thái vào lệnh (cập nhật mỗi giây theo giá live): VÀO NGAY (NOW) khi giá live trong Entry ±0,25×ATR(H1) hoặc ở phía có lợi hơn Entry (BUY giá < Entry, SELL giá > Entry — kèm nhãn "giá tốt hơn Entry"); CHỜ LIMIT khi giá đã chạy xa Entry theo hướng có lợi (>0,25×ATR) nhưng chưa quá 1,0×ATR và còn hiệu lực — chờ giá hồi về Entry rồi đặt limit tại Entry; KHÔNG NÊN VÀO NỮA khi giá đã chạm/vượt TP1, hoặc cách Entry quá 1,0×ATR, hoặc đã quá giờ hết hiệu lực (giờ ra tín hiệu + 1 giờ). Thứ tự ưu tiên: KHÔNG NÊN VÀO NỮA trước, rồi VÀO NGAY, rồi CHỜ LIMIT.',
      'TP1 = tầng T1 của thang TP; nếu chưa có thang TP riêng thì TP1 = Entry ± 1×ATR(H1) theo hướng.',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quy tắc Swing đang áp dụng',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...rules.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $r'),
                )),
          ],
        ),
      ),
    );
  }
}
