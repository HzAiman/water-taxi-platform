import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:operator_app/data/repositories/booking_repository.dart';

enum SummaryPeriod { daily, weekly, monthly, yearly, custom }

enum HistoryFilter { all, completed, cancelled, active }

class StatementRecord {
  const StatementRecord({
    required this.filePath,
    required this.fileName,
    required this.period,
    required this.generatedAt,
    required this.totalEarnings,
    required this.completedRides,
    this.periodStart,
    this.periodEnd,
  });

  final String filePath;
  final String fileName;
  final SummaryPeriod period;
  final DateTime generatedAt;
  final double totalEarnings;
  final int completedRides;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  Map<String, dynamic> toMap() => {
    'filePath': filePath,
    'fileName': fileName,
    'period': period.name,
    'generatedAt': generatedAt.toIso8601String(),
    'totalEarnings': totalEarnings,
    'completedRides': completedRides,
    if (periodStart != null) 'periodStart': periodStart!.toIso8601String(),
    if (periodEnd != null) 'periodEnd': periodEnd!.toIso8601String(),
  };

  static StatementRecord fromMap(Map<String, dynamic> map) {
    return StatementRecord(
      filePath: (map['filePath'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      period: _periodFromName((map['period'] ?? '').toString()),
      generatedAt:
          DateTime.tryParse((map['generatedAt'] ?? '').toString()) ??
          DateTime.now(),
      totalEarnings: (map['totalEarnings'] is num)
          ? (map['totalEarnings'] as num).toDouble()
          : 0.0,
      completedRides: (map['completedRides'] is num)
          ? (map['completedRides'] as num).toInt()
          : 0,
      periodStart: DateTime.tryParse((map['periodStart'] ?? '').toString()),
      periodEnd: DateTime.tryParse((map['periodEnd'] ?? '').toString()),
    );
  }

  static SummaryPeriod _periodFromName(String raw) {
    return SummaryPeriod.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => SummaryPeriod.daily,
    );
  }
}

extension SummaryPeriodX on SummaryPeriod {
  String get label {
    switch (this) {
      case SummaryPeriod.daily:
        return 'Daily';
      case SummaryPeriod.weekly:
        return 'Weekly';
      case SummaryPeriod.monthly:
        return 'Monthly';
      case SummaryPeriod.yearly:
        return 'Yearly';
      case SummaryPeriod.custom:
        return 'Custom';
    }
  }
}

extension HistoryFilterX on HistoryFilter {
  String get label {
    switch (this) {
      case HistoryFilter.all:
        return 'All';
      case HistoryFilter.completed:
        return 'Completed';
      case HistoryFilter.cancelled:
        return 'Cancelled';
      case HistoryFilter.active:
        return 'Active';
    }
  }
}

class OperatorTransactionSummaryViewModel extends ChangeNotifier {
  OperatorTransactionSummaryViewModel({
    required BookingRepository bookingRepository,
    required String operatorId,
    String? operatorName,
    String? displayOperatorId,
  }) : _bookingRepository = bookingRepository,
       _operatorId = operatorId,
       _operatorName = operatorName?.trim().isNotEmpty == true
           ? operatorName!.trim()
           : 'Operator',
       _displayOperatorId = displayOperatorId?.trim().isNotEmpty == true
           ? displayOperatorId!.trim()
           : operatorId;

  static const _statementStoragePrefix = 'operator_statement_records_v1_';

  final BookingRepository _bookingRepository;
  final String _operatorId;
  final String _operatorName;
  final String _displayOperatorId;

  StreamSubscription<List<BookingModel>>? _subscription;
  List<BookingModel> _allBookings = const [];
  List<StatementRecord> _statements = const [];
  bool _isLoading = true;
  String? _error;
  bool _isExporting = false;
  SummaryPeriod _selectedPeriod = SummaryPeriod.daily;
  DateTime? _customPeriodStart;
  DateTime? _customPeriodEnd;
  HistoryFilter _selectedHistoryFilter = HistoryFilter.all;
  String _historySearchQuery = '';

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isExporting => _isExporting;
  SummaryPeriod get selectedPeriod => _selectedPeriod;
  String get selectedPeriodRangeLabel =>
      _formatPeriodRange(_selectedPeriodRange(DateTime.now()));
  DateTime? get customPeriodStart => _customPeriodStart;
  DateTime? get customPeriodEnd => _customPeriodEnd;
  HistoryFilter get selectedHistoryFilter => _selectedHistoryFilter;
  String get historySearchQuery => _historySearchQuery;
  List<StatementRecord> get statements => _statements;

  int get completedToday =>
      _completedForWindow(_startOfDay(DateTime.now()), DateTime.now());

  int get completedThisWeek =>
      _completedForWindow(_startOfWeek(DateTime.now()), DateTime.now());

  int get completedThisMonth =>
      _completedForWindow(_startOfMonth(DateTime.now()), DateTime.now());

  double get selectedPeriodEarnings => _bookingsForSelectedPeriod
      .where((b) => b.status == BookingStatus.completed)
      .fold(0.0, (sum, b) => sum + _fareOf(b));

  int get selectedPeriodCancelled => _bookingsForSelectedPeriod
      .where((b) => b.status == BookingStatus.cancelled)
      .length;

  int get selectedPeriodPendingOrActive => _bookingsForSelectedPeriod
      .where(
        (b) =>
            b.status == BookingStatus.pending ||
            b.status == BookingStatus.accepted ||
            b.status == BookingStatus.onTheWay,
      )
      .length;

  List<BookingModel> get historyForSelectedPeriod {
    final filtered = _bookingsForSelectedPeriod.where((b) {
      final matchesQuery = _matchesSearchQuery(b, _historySearchQuery);
      if (!matchesQuery) return false;

      switch (_selectedHistoryFilter) {
        case HistoryFilter.all:
          return true;
        case HistoryFilter.completed:
          return b.status == BookingStatus.completed;
        case HistoryFilter.cancelled:
          return b.status == BookingStatus.cancelled;
        case HistoryFilter.active:
          return b.status == BookingStatus.pending ||
              b.status == BookingStatus.accepted ||
              b.status == BookingStatus.onTheWay;
      }
    });

    final list = filtered.toList()
      ..sort((a, b) {
        final at = a.updatedAt ?? a.createdAt;
        final bt = b.updatedAt ?? b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    return list;
  }

  List<BookingModel> get unfilteredHistoryForSelectedPeriod {
    final list = _bookingsForSelectedPeriod.toList()
      ..sort((a, b) {
        final at = a.updatedAt ?? a.createdAt;
        final bt = b.updatedAt ?? b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    return list;
  }

  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    await _loadStatements();

    _subscription = _bookingRepository
        .streamOperatorBookingHistory(_operatorId)
        .listen(
          (bookings) {
            _allBookings = bookings;
            _isLoading = false;
            _error = null;
            notifyListeners();
          },
          onError: (Object e) {
            _isLoading = false;
            _error = 'Failed to load ride history: $e';
            notifyListeners();
          },
        );
  }

  void selectPeriod(SummaryPeriod period) {
    if (_selectedPeriod == period) return;
    _selectedPeriod = period;
    notifyListeners();
  }

  void selectCustomPeriod(DateTime start, DateTime end) {
    final normalizedStart = _startOfDay(start);
    final normalizedEnd = _endOfDay(end);
    _customPeriodStart = normalizedStart.isAfter(normalizedEnd)
        ? _startOfDay(end)
        : normalizedStart;
    _customPeriodEnd = normalizedStart.isAfter(normalizedEnd)
        ? _endOfDay(start)
        : normalizedEnd;
    _selectedPeriod = SummaryPeriod.custom;
    notifyListeners();
  }

  void selectHistoryFilter(HistoryFilter filter) {
    if (_selectedHistoryFilter == filter) return;
    _selectedHistoryFilter = filter;
    notifyListeners();
  }

  void setHistorySearchQuery(String query) {
    _historySearchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  Future<OperationResult> exportSelectedPeriodPdf() async {
    if (_isExporting) {
      return const OperationFailure(
        'Export in progress',
        'Please wait for the current export to finish.',
        isInfo: true,
      );
    }

    _isExporting = true;
    notifyListeners();

    try {
      final data = historyForSelectedPeriod;
      final bytes = await _buildPdfBytes(data);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final period = selectedPeriod.label.toLowerCase();
      final fileName = 'operator_statement_${period}_$timestamp.pdf';
      final filePath = await _persistPdf(bytes, fileName);
      final periodRange = _selectedPeriodRange(DateTime.now());

      final completed = data
          .where((b) => b.status == BookingStatus.completed)
          .length;
      final record = StatementRecord(
        filePath: filePath,
        fileName: fileName,
        period: _selectedPeriod,
        generatedAt: DateTime.now(),
        totalEarnings: selectedPeriodEarnings,
        completedRides: completed,
        periodStart: periodRange.start,
        periodEnd: periodRange.end,
      );

      _statements = [record, ..._statements];
      await _saveStatements();

      await Printing.layoutPdf(onLayout: (_) => bytes, name: fileName);

      return const OperationSuccess(
        'Statement generated, saved, and ready to view or print.',
      );
    } catch (e) {
      return OperationFailure(
        'Statement export failed',
        'Could not generate PDF statement: $e',
      );
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<OperationResult> viewStatement(StatementRecord record) async {
    try {
      final file = File(record.filePath);
      if (!await file.exists()) {
        return const OperationFailure(
          'Statement missing',
          'The saved statement file was not found on this device.',
          isInfo: true,
        );
      }

      final bytes = await file.readAsBytes();
      await Printing.layoutPdf(onLayout: (_) => bytes, name: record.fileName);
      return const OperationSuccess('Statement opened successfully.');
    } catch (e) {
      return OperationFailure('Open failed', 'Could not open statement: $e');
    }
  }

  Future<OperationResult> shareStatement(StatementRecord record) async {
    try {
      final file = File(record.filePath);
      if (!await file.exists()) {
        return const OperationFailure(
          'Statement missing',
          'The saved statement file was not found on this device.',
          isInfo: true,
        );
      }

      final bytes = await file.readAsBytes();
      await Printing.sharePdf(bytes: bytes, filename: record.fileName);
      return const OperationSuccess('Statement shared successfully.');
    } catch (e) {
      return OperationFailure('Share failed', 'Could not share statement: $e');
    }
  }

  Future<OperationResult> deleteStatement(StatementRecord record) async {
    try {
      final file = File(record.filePath);
      if (await file.exists()) {
        await file.delete();
      }

      _statements = _statements
          .where((s) => s.filePath != record.filePath)
          .toList();
      await _saveStatements();
      notifyListeners();

      return const OperationSuccess('Statement removed.');
    } catch (e) {
      return OperationFailure(
        'Delete failed',
        'Could not delete statement: $e',
      );
    }
  }

  Future<Uint8List> _buildPdfBytes(List<BookingModel> data) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final completedTrips = data
        .where((booking) => booking.status == BookingStatus.completed)
        .toList(growable: false);
    final periodRange = _selectedPeriodRange(now);
    final logo = await _loadStatementLogo();
    final brandOrange = PdfColor.fromHex('#FF7A00');
    final brandMagenta = PdfColor.fromHex('#CA4B8C');
    final ink = PdfColor.fromHex('#1A1A1A');
    final muted = PdfColor.fromHex('#666666');
    final softBorder = PdfColor.fromHex('#DDE5F0');
    final softFill = PdfColor.fromHex('#FFF3EA');
    final routeHeader = _pdfSafe('Route');
    final passengerHeader = _pdfSafe('Pax');
    final adultsHeader = _pdfSafe('Adults');
    final childrenHeader = _pdfSafe('Children');
    final fareHeader = _pdfSafe('Fare');
    final tripDateHeader = _pdfSafe('Trip Date');
    final bookingTimeHeader = _pdfSafe('Booking Time');

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null)
                pw.Container(
                  width: 44,
                  height: 44,
                  margin: const pw.EdgeInsets.only(right: 12),
                  child: pw.Image(logo),
                ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _pdfSafe('Melaka Water Taxi'),
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: brandMagenta,
                      ),
                    ),
                    pw.Text(
                      _pdfSafe(
                        'Operator Income Statement (${selectedPeriod.label})',
                      ),
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Container(height: 3, color: brandOrange)),
              pw.Expanded(child: pw.Container(height: 3, color: brandMagenta)),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FAFBFE'),
              border: pw.Border.all(color: softBorder),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _pdfMetaLine('Operator', _operatorName, ink, muted),
                      _pdfMetaLine(
                        'Operator ID',
                        _displayOperatorId,
                        ink,
                        muted,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 18),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _pdfMetaLine(
                        'Statement Period',
                        _formatPeriodRange(periodRange),
                        ink,
                        muted,
                      ),
                      _pdfMetaLine('Generated', _fmt(now), ink, muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: softFill,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              children: [
                _pdfSummaryMetric(
                  'Completed Rides',
                  completedTrips.length.toString(),
                  ink,
                  muted,
                ),
                _pdfSummaryMetric(
                  'Cancelled Rides',
                  selectedPeriodCancelled.toString(),
                  ink,
                  muted,
                ),
                _pdfSummaryMetric(
                  'Total Earnings',
                  _currency(selectedPeriodEarnings),
                  brandMagenta,
                  muted,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Trip Details',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
          pw.SizedBox(height: 8),
          if (completedTrips.isEmpty)
            pw.Text(_pdfSafe('No completed trips found for this period.'))
          else
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: softBorder, width: 0.6),
              headerDecoration: pw.BoxDecoration(color: brandMagenta),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(fontSize: 8, color: ink),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(3.2),
                1: pw.FlexColumnWidth(0.7),
                2: pw.FlexColumnWidth(0.8),
                3: pw.FlexColumnWidth(0.9),
                4: pw.FlexColumnWidth(1.1),
                5: pw.FlexColumnWidth(1.3),
                6: pw.FlexColumnWidth(1.2),
              },
              headers: [
                routeHeader,
                passengerHeader,
                adultsHeader,
                childrenHeader,
                fareHeader,
                tripDateHeader,
                bookingTimeHeader,
              ],
              data: completedTrips
                  .map(
                    (b) => [
                      _pdfSafe(_routeLabel(b)),
                      b.passengerCount.toString(),
                      b.adultCount.toString(),
                      b.childCount.toString(),
                      _currency(_fareOf(b)),
                      _formatPdfDate(b.updatedAt ?? b.createdAt),
                      _formatPdfTime(b.createdAt),
                    ],
                  )
                  .toList(),
            ),
          pw.Spacer(),
          pw.Divider(color: softBorder),
          pw.Text(
            _pdfSafe('Generated by Melaka Water Taxi Operator App'),
            style: pw.TextStyle(fontSize: 9, color: muted),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<String> _persistPdf(Uint8List bytes, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final statementsDir = Directory('${dir.path}/operator_statements');
    if (!await statementsDir.exists()) {
      await statementsDir.create(recursive: true);
    }

    final file = File('${statementsDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _loadStatements() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statementStorageKey);
    if (raw == null || raw.isEmpty) {
      _statements = const [];
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _statements = const [];
        return;
      }

      _statements = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(StatementRecord.fromMap)
          .toList();
    } catch (_) {
      _statements = const [];
    }
  }

  Future<void> _saveStatements() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_statements.map((s) => s.toMap()).toList());
    await prefs.setString(_statementStorageKey, encoded);
  }

  String get _statementStorageKey => '$_statementStoragePrefix$_operatorId';

  bool _matchesSearchQuery(BookingModel b, String query) {
    if (query.isEmpty) return true;

    final haystack = [
      b.bookingId,
      b.userName,
      b.userPhone,
      b.origin,
      b.destination,
      b.status.firestoreValue,
    ].join(' ').toLowerCase();

    return haystack.contains(query);
  }

  Iterable<BookingModel> get _bookingsForSelectedPeriod {
    final now = DateTime.now();
    final range = _selectedPeriodRange(now);

    return _allBookings.where((b) {
      final t = b.updatedAt ?? b.createdAt;
      if (t == null) return false;
      return !t.isBefore(range.start) && !t.isAfter(range.end);
    });
  }

  int _completedForWindow(DateTime start, DateTime end) {
    return _allBookings.where((b) {
      if (b.status != BookingStatus.completed) return false;
      final t = b.updatedAt ?? b.createdAt;
      if (t == null) return false;
      return !t.isBefore(start) && !t.isAfter(end);
    }).length;
  }

  double _fareOf(BookingModel b) => b.totalFare;

  static DateTime _startOfDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  static DateTime _startOfWeek(DateTime dt) {
    final weekday = dt.weekday;
    return _startOfDay(dt.subtract(Duration(days: weekday - 1)));
  }

  static DateTime _startOfMonth(DateTime dt) => DateTime(dt.year, dt.month, 1);

  static DateTime _startOfYear(DateTime dt) => DateTime(dt.year, 1, 1);

  static DateTime _endOfDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, 23, 59, 59, 999, 999);

  static DateTime _endOfMonth(DateTime dt) => DateTime(
    dt.year,
    dt.month + 1,
    1,
  ).subtract(const Duration(microseconds: 1));

  static DateTime _endOfYear(DateTime dt) =>
      DateTime(dt.year + 1, 1, 1).subtract(const Duration(microseconds: 1));

  _StatementPeriodRange _selectedPeriodRange(DateTime now) {
    return switch (_selectedPeriod) {
      SummaryPeriod.daily => _StatementPeriodRange(
        start: _startOfDay(now),
        end: _endOfDay(now),
      ),
      SummaryPeriod.weekly => _StatementPeriodRange(
        start: _startOfWeek(now),
        end: _endOfDay(_startOfWeek(now).add(const Duration(days: 6))),
      ),
      SummaryPeriod.monthly => _StatementPeriodRange(
        start: _startOfMonth(now),
        end: _endOfMonth(now),
      ),
      SummaryPeriod.yearly => _StatementPeriodRange(
        start: _startOfYear(now),
        end: _endOfYear(now),
      ),
      SummaryPeriod.custom => _StatementPeriodRange(
        start: _customPeriodStart ?? _startOfDay(now),
        end: _customPeriodEnd ?? _endOfDay(now),
      ),
    };
  }

  static String _currency(double value) => 'RM ${value.toStringAsFixed(2)}';

  static String _routeLabel(BookingModel booking) {
    final origin = booking.origin.trim().isEmpty ? 'Pickup' : booking.origin;
    final destination = booking.destination.trim().isEmpty
        ? 'Dropoff'
        : booking.destination;
    return '$origin > $destination';
  }

  static String _pdfSafe(String value) {
    return value
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2022', '-');
  }

  static String _fmt(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  static String _formatPdfDate(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatPdfTime(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String _formatPeriodRange(_StatementPeriodRange range) {
    final start = _formatStatementDate(range.start);
    final end = _formatStatementDate(range.end);
    return start == end ? start : '$start - $end';
  }

  static String _formatStatementDate(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  static pw.Widget _pdfMetaLine(
    String label,
    String value,
    PdfColor ink,
    PdfColor muted,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: muted,
              ),
            ),
            pw.TextSpan(
              text: _pdfSafe(value),
              style: pw.TextStyle(fontSize: 10, color: ink),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfSummaryMetric(
    String label,
    String value,
    PdfColor valueColor,
    PdfColor labelColor,
  ) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: valueColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _pdfSafe(label),
            style: pw.TextStyle(fontSize: 9, color: labelColor),
          ),
        ],
      ),
    );
  }

  static Future<pw.MemoryImage?> _loadStatementLogo() async {
    try {
      final data = await rootBundle.load('assets/app_icon/icon.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class _StatementPeriodRange {
  const _StatementPeriodRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}
