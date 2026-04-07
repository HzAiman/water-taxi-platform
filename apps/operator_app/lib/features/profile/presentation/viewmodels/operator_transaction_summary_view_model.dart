import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:operator_app/data/repositories/booking_repository.dart';

enum SummaryPeriod { daily, weekly, monthly }

enum HistoryFilter { all, completed, cancelled, active }

class StatementRecord {
  const StatementRecord({
    required this.filePath,
    required this.fileName,
    required this.period,
    required this.generatedAt,
    required this.totalEarnings,
    required this.completedRides,
  });

  final String filePath;
  final String fileName;
  final SummaryPeriod period;
  final DateTime generatedAt;
  final double totalEarnings;
  final int completedRides;

  Map<String, dynamic> toMap() => {
    'filePath': filePath,
    'fileName': fileName,
    'period': period.name,
    'generatedAt': generatedAt.toIso8601String(),
    'totalEarnings': totalEarnings,
    'completedRides': completedRides,
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
  }) : _bookingRepository = bookingRepository,
       _operatorId = operatorId;

  static const _statementStoragePrefix = 'operator_statement_records_v1_';

  final BookingRepository _bookingRepository;
  final String _operatorId;

  StreamSubscription<List<BookingModel>>? _subscription;
  List<BookingModel> _allBookings = const [];
  List<StatementRecord> _statements = const [];
  bool _isLoading = true;
  String? _error;
  bool _isExporting = false;
  SummaryPeriod _selectedPeriod = SummaryPeriod.daily;
  HistoryFilter _selectedHistoryFilter = HistoryFilter.all;
  String _historySearchQuery = '';

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isExporting => _isExporting;
  SummaryPeriod get selectedPeriod => _selectedPeriod;
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
      );

      _statements = [record, ..._statements];
      await _saveStatements();

      await Printing.sharePdf(bytes: bytes, filename: fileName);

      return const OperationSuccess(
        'Statement generated, saved, and ready to share.',
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

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            'Operator Income Statement (${selectedPeriod.label})',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Generated: ${_fmt(now)}'),
          pw.Text('Operator ID: $_operatorId'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Summary',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Bullet(
            text:
                'Completed rides: ${data.where((b) => b.status == BookingStatus.completed).length}',
          ),
          pw.Bullet(
            text: 'Pending or active rides: $selectedPeriodPendingOrActive',
          ),
          pw.Bullet(text: 'Cancelled rides: $selectedPeriodCancelled'),
          pw.Bullet(
            text: 'Total earnings: ${_currency(selectedPeriodEarnings)}',
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Detailed Ride History',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (data.isEmpty)
            pw.Text('No rides found for this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Booking', 'Status', 'Fare', 'Updated'],
              data: data
                  .map(
                    (b) => [
                      b.bookingId,
                      b.status.firestoreValue,
                      _currency(_fareOf(b)),
                      _fmt(b.updatedAt ?? b.createdAt),
                    ],
                  )
                  .toList(),
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
    final start = switch (_selectedPeriod) {
      SummaryPeriod.daily => _startOfDay(now),
      SummaryPeriod.weekly => _startOfWeek(now),
      SummaryPeriod.monthly => _startOfMonth(now),
    };

    return _allBookings.where((b) {
      final t = b.updatedAt ?? b.createdAt;
      if (t == null) return false;
      return !t.isBefore(start) && !t.isAfter(now);
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

  static String _currency(double value) => 'RM ${value.toStringAsFixed(2)}';

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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
