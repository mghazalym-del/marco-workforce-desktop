import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';

class MonthlyCostBatchPage extends StatefulWidget {
  const MonthlyCostBatchPage({super.key});

  @override
  State<MonthlyCostBatchPage> createState() => _MonthlyCostBatchPageState();
}

class _MonthlyCostBatchPageState extends State<MonthlyCostBatchPage> {
  late ApiClient _api;

  bool _initialized = false;
  bool _loadingProjects = false;
  bool _loadingExistingBatch = false;
  bool _validating = false;
  bool _generating = false;
  bool _submitting = false;
  bool _approving = false;
  bool _rejecting = false;
  bool _exporting = false;

  String? _error;
  String? _actionMessage;

  List<Map<String, dynamic>> _projects = [];
  String? _selectedProjectId;

  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _selectedOption = 'OPTION1';

  Map<String, dynamic>? _validationData;
  Map<String, dynamic>? _generationData;
  Map<String, dynamic>? _batchDetail;
  List<Map<String, dynamic>> _batchList = [];

  final TextEditingController _workerSearchController =
      TextEditingController();
  String _workerSearchText = '';
  String _selectedWorkerFilter = 'ALL';

  DateTime? _fromDate;
  DateTime? _toDate;
  String _sortOption = 'DIFF_DESC';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<AppState>().api;

    if (!_initialized) {
      _initialized = true;
      _loadProjects();
    }
  }

  @override
  void dispose() {
    _workerSearchController.dispose();
    super.dispose();
  }

  String _safe(dynamic v) => (v ?? '').toString();

  String _monthValue(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-01";
  }

  String _monthLabel(DateTime d) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return "${months[d.month - 1]} ${d.year}";
  }

  String _displayBatchMonth(dynamic raw) {
    final s = _safe(raw).trim();
    if (s.isEmpty) return '-';

    DateTime? dt;
    try {
      dt = DateTime.parse(s).toLocal();
    } catch (_) {
      dt = null;
    }

    final source = dt != null
        ? DateTime(dt.year, dt.month, 1)
        : (() {
            final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(s);
            if (m == null) return null;
            final year = int.tryParse(m.group(1)!);
            final month = int.tryParse(m.group(2)!);
            if (year == null || month == null || month < 1 || month > 12) {
              return null;
            }
            return DateTime(year, month, 1);
          })();

    if (source == null) return s;

    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    return '${months[source.month - 1]} ${source.year}';
  }

  String _displayDate(dynamic raw) {
    final s = _safe(raw).trim();
    if (s.isEmpty) return '-';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _minutesToHoursText(dynamic raw) {
    final text = _safe(raw).trim();
    if (text.isEmpty) return '-';

    final minutes = double.tryParse(text);
    if (minutes == null) return '-';

    final hours = minutes / 60.0;
    return hours.toStringAsFixed(2);
  }

  String _hoursFromMinutes(double minutes) {
    return (minutes / 60.0).toStringAsFixed(2);
  }

  String _fileSafe(String value) {
    return value.replaceAll(RegExp(r'[^\w\-]+'), '_');
  }

  String _timestamp() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_"
        "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}";
  }

  DateTime? _parseWorkDate(dynamic raw) {
    final s = _safe(raw).trim();
    if (s.isEmpty) return null;

    try {
      final dt = DateTime.parse(s);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      return null;
    }
  }

  bool _matchesDateFilter(dynamic rawDate) {
    final dt = _parseWorkDate(rawDate);

    if ((_fromDate == null && _toDate == null) || dt == null) {
      return true;
    }

    if (_fromDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      if (dt.isBefore(from)) return false;
    }

    if (_toDate != null) {
      final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
      if (dt.isAfter(to)) return false;
    }

    return true;
  }

  double _reviewRowDifference(Map<String, dynamic> row) {
    return double.tryParse(_safe(row['difference_minutes'])) ??
        ((double.tryParse(_safe(row['adjusted_minutes'])) ?? 0.0) -
            (double.tryParse(_safe(row['original_minutes'])) ?? 0.0));
  }

  double _fallbackItemDifference(Map<String, dynamic> row) {
    final original =
        double.tryParse(_safe(row['original_total_minutes'])) ?? 0.0;
    final adjusted =
        double.tryParse(_safe(row['adjusted_total_minutes'])) ?? 0.0;
    return adjusted - original;
  }

  Map<String, double> _filteredDetailTotals({
    required bool usingReviewRows,
    required List<Map<String, dynamic>> rows,
  }) {
    double originalMinutes = 0.0;
    double addedMinutes = 0.0;
    double adjustedMinutes = 0.0;

    for (final row in rows) {
      if (usingReviewRows) {
        originalMinutes +=
            double.tryParse(_safe(row['original_minutes'])) ?? 0.0;
        addedMinutes += double.tryParse(_safe(row['added_minutes'])) ?? 0.0;
        adjustedMinutes +=
            double.tryParse(_safe(row['adjusted_minutes'])) ?? 0.0;
      } else {
        originalMinutes +=
            double.tryParse(_safe(row['original_total_minutes'])) ?? 0.0;
        addedMinutes +=
            double.tryParse(_safe(row['added_or_distributed_minutes'])) ?? 0.0;
        adjustedMinutes +=
            double.tryParse(_safe(row['adjusted_total_minutes'])) ?? 0.0;
      }
    }

    return {
      'original_minutes': originalMinutes,
      'added_minutes': addedMinutes,
      'adjusted_minutes': adjustedMinutes,
      'original_hours': originalMinutes / 60.0,
      'added_hours': addedMinutes / 60.0,
      'adjusted_hours': adjustedMinutes / 60.0,
    };
  }

  Future<void> _printPdf() async {
    if (_batchDetail == null && _generationData == null) return;

    setState(() {
      _exporting = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);

      final pdf = pw.Document();

      final batch = _batchDetail?['batch'] is Map
          ? Map<String, dynamic>.from(_batchDetail!['batch'] as Map)
          : (_generationData ?? <String, dynamic>{});

      final usingReviewRows = _reviewRows.isNotEmpty;
      final rows = usingReviewRows ? _filteredReviewRows : _filteredFallbackItems;
      final workers = _workerSummaries;

      final totals = _filteredDetailTotals(
        usingReviewRows: usingReviewRows,
        rows: rows,
      );

      final baseStyle = pw.TextStyle(font: ttf, fontSize: 10);
      final titleStyle = pw.TextStyle(
        font: ttf,
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
      );
      final sectionStyle = pw.TextStyle(
        font: ttf,
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
      );

      final logoData = await rootBundle.load('assets/logo.png');
      final logoBytes = logoData.buffer.asUint8List();

      pdf.addPage(
        pw.MultiPage(
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated from MARCO Workforce System',
                style: pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          theme: pw.ThemeData.withFont(
            base: ttf,
            bold: ttf,
            italic: ttf,
            boldItalic: ttf,
          ),
          build: (context) => [
            // HEADER
            // HEADER WITH LOGO (FULL REPLACEMENT)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // LOGO
                pw.Container(
                  width: 40,
                  height: 40,
                  child: pw.Image(pw.MemoryImage(logoBytes)),
                ),

                pw.SizedBox(width: 10),

                // TEXT BLOCK
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'MARCO Workforce',
                      style: pw.TextStyle(
                        font: ttf,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Monthly Cost Batch Report',
                      style: pw.TextStyle(font: ttf, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1.5),

            // META GRID
            pw.Wrap(
              spacing: 20,
              runSpacing: 6,
              children: [
                pw.Text('Project: ${_safe(batch['project_id'])}', style: baseStyle),
                pw.Text('Month: ${_displayBatchMonth(batch['cost_month'])}', style: baseStyle),
                pw.Text('Option: ${_safe(batch['option_type'])}', style: baseStyle),
                pw.Text('Status: ${_safe(batch['status'])}', style: baseStyle),
                pw.Text('Batch ID: ${_safe(batch['batch_id'])}', style: baseStyle),
              ],
            ),

            pw.SizedBox(height: 12),

            // SUMMARY BOX
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Rows: ${rows.length}', style: baseStyle),
                  pw.Text('Original: ${_hoursFromMinutes(totals['original_minutes'] ?? 0)} hr', style: baseStyle),
                  pw.Text('Added: ${_hoursFromMinutes(totals['added_minutes'] ?? 0)} hr', style: baseStyle),
                  pw.Text('Adjusted: ${_hoursFromMinutes(totals['adjusted_minutes'] ?? 0)} hr', style: baseStyle),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // WORKER TABLE
            pw.Text('Worker Summary', style: sectionStyle),
            pw.SizedBox(height: 6),

            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FixedColumnWidth(60),
                1: const pw.FlexColumnWidth(),
                2: const pw.FixedColumnWidth(50),
                3: const pw.FixedColumnWidth(50),
                4: const pw.FixedColumnWidth(50),
                5: const pw.FixedColumnWidth(50),
              },
              children: [
                // HEADER
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _th('ID'),
                    _th('Name'),
                    _th('Orig'),
                    _th('Add'),
                    _th('Adj'),
                    _th('Diff'),
                  ],
                ),

                // DATA
                ...workers.map((w) {
                  final original = (w['original_minutes'] as double?) ?? 0;
                  final added = (w['added_minutes'] as double?) ?? 0;
                  final adjusted = (w['adjusted_minutes'] as double?) ?? 0;
                  final diff = (w['difference_minutes'] as double?) ?? 0;

                  return pw.TableRow(
                    children: [
                      _tc(_safe(w['employee_id'])),
                      _tc(_safe(w['employee_name']), alignLeft: true),
                      _tc(_hoursFromMinutes(original), isNumber: true),
                      _tc(_hoursFromMinutes(added), isNumber: true),
                      _tc(_hoursFromMinutes(adjusted), isNumber: true),
                      _tc(_hoursFromMinutes(diff), isNumber: true),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 16),

            // DETAILS TABLE
            pw.Text('Details', style: sectionStyle),
            pw.SizedBox(height: 6),

            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FixedColumnWidth(70),
                1: const pw.FixedColumnWidth(70),
                2: const pw.FixedColumnWidth(70),
                3: const pw.FixedColumnWidth(50),
                4: const pw.FixedColumnWidth(50),
                5: const pw.FixedColumnWidth(50),
                6: const pw.FixedColumnWidth(50),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _th('Date'),
                    _th('Worker'),
                    _th('Project'),
                    _th('Orig'),
                    _th('Add'),
                    _th('Adj'),
                    _th('Diff'),
                  ],
                ),

                ...rows.map((r) {
                  final original = double.tryParse(
                        _safe(usingReviewRows
                            ? r['original_minutes']
                            : r['original_total_minutes']),
                      ) ??
                      0;

                  final added = double.tryParse(
                        _safe(usingReviewRows
                            ? r['added_minutes']
                            : r['added_or_distributed_minutes']),
                      ) ??
                      0;

                  final adjusted = double.tryParse(
                        _safe(usingReviewRows
                            ? r['adjusted_minutes']
                            : r['adjusted_total_minutes']),
                      ) ??
                      0;

                  final diff = adjusted - original;

                  return pw.TableRow(
                    children: [
                      _tc(_displayDate(r['work_date'])),
                      _tc(_safe(r['employee_id'])),
                      _tc(_safe(r['project_id'])),
                      _tc(_hoursFromMinutes(original), isNumber: true),
                      _tc(_hoursFromMinutes(added), isNumber: true),
                      _tc(_hoursFromMinutes(adjusted), isNumber: true),
                      _tc(_hoursFromMinutes(diff), isNumber: true),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 30),

            // SIGNATURES
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(children: [
                  pw.Text('Cost Controller'),
                  pw.SizedBox(height: 30),
                  pw.Container(width: 150, height: 1, color: PdfColors.black),
                ]),
                pw.Column(children: [
                  pw.Text('Project Manager'),
                  pw.SizedBox(height: 30),
                  pw.Container(width: 150, height: 1, color: PdfColors.black),
                ]),
              ],
            ),
          ],
        ),
      );

      final bytes = await pdf.save();

      final projectId = _fileSafe(
        _safe(batch['project_id']).isEmpty
            ? (_selectedProjectId ?? 'project')
            : _safe(batch['project_id']),
      );
      final option = _fileSafe(_selectedOption.toLowerCase());
      final month =
          _monthValue(_selectedMonth).substring(0, 7).replaceAll('-', '_');
      final fileName =
          'monthly_cost_${projectId}_${month}_${option}_${_timestamp()}.pdf';

      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (format) async => bytes,
          name: fileName,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final fullPath = '${dir.path}/$fileName';
        final outFile = File(fullPath);

        await outFile.writeAsBytes(bytes, flush: true);

        setState(() {
          _actionMessage = 'PDF exported successfully to Documents folder.';
        });

        _showMessage(
          'PDF Successful',
          'PDF file saved to:\n$fullPath',
        );
      }
    } catch (e) {
      _showMessage('PDF Failed', e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  Future<void> _exportToExcel() async {
    if (_batchDetail == null && _generationData == null) return;

    setState(() {
      _exporting = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      final excel = ex.Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != 'Batch Summary') {
        excel.delete(defaultSheet);
      }

      final batch = _batchDetail?['batch'] is Map
          ? Map<String, dynamic>.from(_batchDetail!['batch'] as Map)
          : (_generationData ?? <String, dynamic>{});

      final usingReviewRows = _reviewRows.isNotEmpty;
      final rows = usingReviewRows ? _filteredReviewRows : _filteredFallbackItems;
      final workerSummaries = _workerSummaries;
      final filteredTotals = _filteredDetailTotals(
        usingReviewRows: usingReviewRows,
        rows: rows,
      );

      final summarySheet = excel['Batch Summary'];
      summarySheet.appendRow(['Field', 'Value']);

      void addSummaryRow(String label, dynamic value) {
        summarySheet.appendRow([label, _safe(value)]);
      }

      addSummaryRow('Batch ID', batch['batch_id']);
      addSummaryRow('Project', batch['project_id']);
      addSummaryRow('Month', _displayBatchMonth(batch['cost_month']));
      addSummaryRow('Option', batch['option_type']);
      addSummaryRow('Status', batch['status']);
      addSummaryRow('Generated By', batch['generated_by']);
      addSummaryRow('Generated At', batch['generated_at']);
      addSummaryRow('Submitted By', batch['submitted_by']);
      addSummaryRow('Submitted At', batch['submitted_at']);
      addSummaryRow('Approved By', batch['approved_by']);
      addSummaryRow('Approved At', batch['approved_at']);
      addSummaryRow('Returned By', batch['returned_by']);
      addSummaryRow('Returned At', batch['returned_at']);
      addSummaryRow('Return Reason', batch['return_reason']);

      addSummaryRow('', '');
      addSummaryRow('Active Search', _workerSearchText);
      addSummaryRow('Worker Filter', _selectedWorkerFilter);
      addSummaryRow(
        'From Date',
        _fromDate == null ? '' : _displayDate(_fromDate),
      );
      addSummaryRow(
        'To Date',
        _toDate == null ? '' : _displayDate(_toDate),
      );
      addSummaryRow('Sort', _sortOption);

      addSummaryRow('', '');
      addSummaryRow('Filtered Detail Rows', rows.length);
      addSummaryRow(
        'Filtered Original Hours',
        _hoursFromMinutes(filteredTotals['original_minutes'] ?? 0.0),
      );
      addSummaryRow(
        'Filtered Added Hours',
        _hoursFromMinutes(filteredTotals['added_minutes'] ?? 0.0),
      );
      addSummaryRow(
        'Filtered Adjusted Hours',
        _hoursFromMinutes(filteredTotals['adjusted_minutes'] ?? 0.0),
      );

      final workerSheet = excel['Worker Summary'];
      workerSheet.appendRow([
        'Employee ID',
        'Employee Name',
        'Original Minutes',
        'Original Hours',
        'Added Minutes',
        'Added Hours',
        'Adjusted Minutes',
        'Adjusted Hours',
        'Difference Minutes',
        'Difference Hours',
      ]);

      for (final w in workerSummaries) {
        final original = (w['original_minutes'] as double?) ?? 0.0;
        final added = (w['added_minutes'] as double?) ?? 0.0;
        final adjusted = (w['adjusted_minutes'] as double?) ?? 0.0;
        final difference = (w['difference_minutes'] as double?) ?? 0.0;

        workerSheet.appendRow([
          _safe(w['employee_id']),
          _safe(w['employee_name']),
          original.toStringAsFixed(2),
          _hoursFromMinutes(original),
          added.toStringAsFixed(2),
          _hoursFromMinutes(added),
          adjusted.toStringAsFixed(2),
          _hoursFromMinutes(adjusted),
          difference.toStringAsFixed(2),
          _hoursFromMinutes(difference),
        ]);
      }

      final detailSheet = excel['Review Details'];
      detailSheet.appendRow([
        'Date',
        'Employee ID',
        'Employee Name',
        'Project',
        'Original Minutes',
        'Original Hours',
        'Added Minutes',
        'Added Hours',
        'Adjusted Minutes',
        'Adjusted Hours',
        'Difference Minutes',
        'Difference Hours',
      ]);

      for (final row in rows) {
        if (usingReviewRows) {
          final original =
              double.tryParse(_safe(row['original_minutes'])) ?? 0.0;
          final added = double.tryParse(_safe(row['added_minutes'])) ?? 0.0;
          final adjusted =
              double.tryParse(_safe(row['adjusted_minutes'])) ?? 0.0;
          final diff = _reviewRowDifference(row);

          detailSheet.appendRow([
            _displayDate(row['work_date']),
            _safe(row['employee_id']),
            _safe(row['employee_name']),
            _safe(row['project_id']),
            original.toStringAsFixed(2),
            _hoursFromMinutes(original),
            added.toStringAsFixed(2),
            _hoursFromMinutes(added),
            adjusted.toStringAsFixed(2),
            _hoursFromMinutes(adjusted),
            diff.toStringAsFixed(2),
            _hoursFromMinutes(diff),
          ]);
        } else {
          final original =
              double.tryParse(_safe(row['original_total_minutes'])) ?? 0.0;
          final added =
              double.tryParse(_safe(row['added_or_distributed_minutes'])) ?? 0.0;
          final adjusted =
              double.tryParse(_safe(row['adjusted_total_minutes'])) ?? 0.0;
          final diff = adjusted - original;

          detailSheet.appendRow([
            _displayDate(row['work_date']),
            _safe(row['employee_id']),
            _safe(row['employee_name']),
            _safe(row['project_id']),
            original.toStringAsFixed(2),
            _hoursFromMinutes(original),
            added.toStringAsFixed(2),
            _hoursFromMinutes(added),
            adjusted.toStringAsFixed(2),
            _hoursFromMinutes(adjusted),
            diff.toStringAsFixed(2),
            _hoursFromMinutes(diff),
          ]);
        }
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Excel export failed: no file bytes generated.');
      }

      final projectId = _fileSafe(
        _safe(batch['project_id']).isEmpty
            ? (_selectedProjectId ?? 'project')
            : _safe(batch['project_id']),
      );
      final option = _fileSafe(_selectedOption.toLowerCase());
      final month =
          _monthValue(_selectedMonth).substring(0, 7).replaceAll('-', '_');
      final fileName =
          'monthly_cost_${projectId}_${month}_${option}_${_timestamp()}.xlsx';

      if (kIsWeb) {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Excel',
              extensions: ['xlsx'],
            ),
          ],
        );

        if (location == null) {
          setState(() {
            _actionMessage = 'Export cancelled.';
          });
          return;
        }

        final file = XFile.fromData(
          Uint8List.fromList(bytes),
          name: fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );

        await file.saveTo(location.path);

        setState(() {
          _actionMessage = 'Excel export completed successfully.';
        });

        _showMessage(
          'Export Successful',
          'Excel file was exported successfully.',
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final fullPath = '${dir.path}/$fileName';
        final outFile = File(fullPath);

        await outFile.writeAsBytes(bytes, flush: true);

        setState(() {
          _actionMessage = 'Excel export completed successfully.';
        });

        _showMessage(
          'Export Successful',
          'Excel file saved to:\n$fullPath',
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
      _showMessage('Export Failed', e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  void _resetReviewTools() {
    _workerSearchText = '';
    _workerSearchController.clear();
    _selectedWorkerFilter = 'ALL';
    _fromDate = null;
    _toDate = null;
    _sortOption = 'DIFF_DESC';
  }

  bool get _hasProject =>
      _selectedProjectId != null && _selectedProjectId!.trim().isNotEmpty;

  bool get _busy =>
      _loadingProjects ||
      _loadingExistingBatch ||
      _validating ||
      _generating ||
      _submitting ||
      _approving ||
      _rejecting ||
      _exporting;

  String get _currentBatchStatus =>
      _safe((_batchDetail?['batch'] ?? _generationData)?['status'])
          .toUpperCase()
          .trim();

  String? get _currentBatchId {
    final batchNode = _batchDetail?['batch'];
    if (batchNode is Map && batchNode['batch_id'] != null) {
      return _safe(batchNode['batch_id']);
    }
    if (_generationData?['batch_id'] != null) {
      return _safe(_generationData!['batch_id']);
    }
    return null;
  }

  bool get _isApprovedLocked =>
      _currentBatchStatus == 'PM_APPROVED' ||
      _currentBatchStatus == 'FINALIZED';

  List<Map<String, dynamic>> get _detailItems {
    final detail = _batchDetail;
    if (detail == null || detail['items'] is! List) {
      return <Map<String, dynamic>>[];
    }
    return List<Map<String, dynamic>>.from(
      (detail['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)),
    );
  }

  List<Map<String, dynamic>> get _reviewRows {
    final detail = _batchDetail;
    if (detail == null || detail['review_rows'] is! List) {
      return <Map<String, dynamic>>[];
    }
    return List<Map<String, dynamic>>.from(
      (detail['review_rows'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)),
    );
  }

  List<String> get _workerFilterOptions {
    final baseRows = _reviewRows.isNotEmpty ? _reviewRows : _detailItems;
    final options = <String>{'ALL'};

    for (final row in baseRows) {
      final id = _safe(row['employee_id']).trim();
      final name = _safe(row['employee_name']).trim();
      if (id.isEmpty && name.isEmpty) continue;
      options.add('$id|$name');
    }

    final list = options.toList();
    list.sort((a, b) {
      if (a == 'ALL') return -1;
      if (b == 'ALL') return 1;
      return a.compareTo(b);
    });
    return list;
  }

  List<Map<String, dynamic>> get _filteredReviewRows {
    final rows = _reviewRows;
    if (rows.isEmpty) return rows;

    final filtered = rows.where((row) {
      final workerId = _safe(row['employee_id']).toLowerCase();
      final workerName = _safe(row['employee_name']).toLowerCase();
      final search = _workerSearchText.trim().toLowerCase();

      final matchesSearch = search.isEmpty ||
          workerId.contains(search) ||
          workerName.contains(search);

      bool matchesFilter = true;
      if (_selectedWorkerFilter != 'ALL') {
        final parts = _selectedWorkerFilter.split('|');
        final filterId = parts.isNotEmpty ? parts.first.trim() : '';
        matchesFilter = workerId == filterId.toLowerCase();
      }

      final matchesDate = _matchesDateFilter(row['work_date']);

      return matchesSearch && matchesFilter && matchesDate;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortOption) {
        case 'DIFF_DESC':
          return _reviewRowDifference(b).compareTo(_reviewRowDifference(a));
        case 'DIFF_ASC':
          return _reviewRowDifference(a).compareTo(_reviewRowDifference(b));
        case 'DATE_ASC':
          return _safe(a['work_date']).compareTo(_safe(b['work_date']));
        case 'DATE_DESC':
          return _safe(b['work_date']).compareTo(_safe(a['work_date']));
        case 'WORKER':
          return _safe(a['employee_id']).compareTo(_safe(b['employee_id']));
        default:
          return 0;
      }
    });

    return filtered;
  }

  List<Map<String, dynamic>> get _filteredFallbackItems {
    final items = _detailItems;
    if (items.isEmpty) return items;

    final filtered = items.where((row) {
      final workerId = _safe(row['employee_id']).toLowerCase();
      final workerName = _safe(row['employee_name']).toLowerCase();
      final search = _workerSearchText.trim().toLowerCase();

      final matchesSearch = search.isEmpty ||
          workerId.contains(search) ||
          workerName.contains(search);

      bool matchesFilter = true;
      if (_selectedWorkerFilter != 'ALL') {
        final parts = _selectedWorkerFilter.split('|');
        final filterId = parts.isNotEmpty ? parts.first.trim() : '';
        matchesFilter = workerId == filterId.toLowerCase();
      }

      final matchesDate = _matchesDateFilter(row['work_date']);

      return matchesSearch && matchesFilter && matchesDate;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortOption) {
        case 'DIFF_DESC':
          return _fallbackItemDifference(b).compareTo(_fallbackItemDifference(a));
        case 'DIFF_ASC':
          return _fallbackItemDifference(a).compareTo(_fallbackItemDifference(b));
        case 'DATE_ASC':
          return _safe(a['work_date']).compareTo(_safe(b['work_date']));
        case 'DATE_DESC':
          return _safe(b['work_date']).compareTo(_safe(a['work_date']));
        case 'WORKER':
          return _safe(a['employee_id']).compareTo(_safe(b['employee_id']));
        default:
          return 0;
      }
    });

    return filtered;
  }

  List<Map<String, dynamic>> get _workerSummaries {
    final usingReviewRows = _reviewRows.isNotEmpty;
    final rows = usingReviewRows ? _filteredReviewRows : _filteredFallbackItems;

    final Map<String, Map<String, dynamic>> grouped = {};

    for (final row in rows) {
      final workerId = _safe(row['employee_id']).trim();
      final workerName = _safe(row['employee_name']).trim();
      if (workerId.isEmpty && workerName.isEmpty) continue;

      final key = workerId;
      grouped.putIfAbsent(key, () {
        return {
          'employee_id': workerId,
          'employee_name': workerName,
          'original_minutes': 0.0,
          'added_minutes': 0.0,
          'adjusted_minutes': 0.0,
          'difference_minutes': 0.0,
        };
      });

      final item = grouped[key]!;

      final original = double.tryParse(
            _safe(usingReviewRows
                ? row['original_minutes']
                : row['original_total_minutes']),
          ) ??
          0.0;

      final added = double.tryParse(
            _safe(usingReviewRows
                ? row['added_minutes']
                : row['added_or_distributed_minutes']),
          ) ??
          0.0;

      final adjusted = double.tryParse(
            _safe(usingReviewRows
                ? row['adjusted_minutes']
                : row['adjusted_total_minutes']),
          ) ??
          0.0;

      final difference = usingReviewRows
          ? _reviewRowDifference(row)
          : _fallbackItemDifference(row);

      item['original_minutes'] =
          (item['original_minutes'] as double) + original;
      item['added_minutes'] = (item['added_minutes'] as double) + added;
      item['adjusted_minutes'] =
          (item['adjusted_minutes'] as double) + adjusted;
      item['difference_minutes'] =
          (item['difference_minutes'] as double) + difference;
    }

    final list = grouped.values.toList();
    list.sort((a, b) => (b['difference_minutes'] as double)
        .compareTo(a['difference_minutes'] as double));
    return list;
  }

  Future<void> _pickMonth() async {
    int tempYear = _selectedMonth.year;
    int tempMonth = _selectedMonth.month;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Select Month'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => setLocal(() => tempYear--),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              tempYear.toString(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setLocal(() => tempYear++),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      itemCount: 12,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.2,
                      ),
                      itemBuilder: (_, i) {
                        final month = i + 1;
                        final selected = month == tempMonth;
                        const labels = [
                          'Jan',
                          'Feb',
                          'Mar',
                          'Apr',
                          'May',
                          'Jun',
                          'Jul',
                          'Aug',
                          'Sep',
                          'Oct',
                          'Nov',
                          'Dec'
                        ];
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setLocal(() => tempMonth = month),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.withOpacity(0.2),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, DateTime(tempYear, tempMonth, 1));
                  },
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month, 1);
      _validationData = null;
      _generationData = null;
      _batchDetail = null;
      _batchList = [];
      _error = null;
      _actionMessage = null;
      _resetReviewTools();
    });

    await _loadExistingBatch();
  }

  Future<void> _pickFromDate() async {
    final initialDate = _fromDate ??
        _toDate ??
        DateTime(_selectedMonth.year, _selectedMonth.month, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _fromDate = DateTime(picked.year, picked.month, picked.day);
      if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
        _toDate = _fromDate;
      }
    });
  }

  Future<void> _pickToDate() async {
    final initialDate = _toDate ??
        _fromDate ??
        DateTime(_selectedMonth.year, _selectedMonth.month, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _toDate = DateTime(picked.year, picked.month, picked.day);
      if (_fromDate != null && _fromDate!.isAfter(_toDate!)) {
        _fromDate = _toDate;
      }
    });
  }

  Future<void> _loadProjects() async {
    setState(() {
      _loadingProjects = true;
      _error = null;
    });

    try {
      final res = await _api.getJson('/projects');

      List<Map<String, dynamic>> projects = [];
      if (res is Map && res['projects'] is List) {
        projects = (res['projects'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (res is Map && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data']);
        if (data['projects'] is List) {
          projects = (data['projects'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      String? nextSelected = _selectedProjectId;
      if (projects.isNotEmpty) {
        final exists = projects.any(
          (p) =>
              _safe(p['project_code']).trim() == (nextSelected ?? '').trim(),
        );
        if (!exists) {
          nextSelected = _safe(projects.first['project_code']).trim();
        }
      } else {
        nextSelected = null;
      }

      setState(() {
        _projects = projects;
        _selectedProjectId = nextSelected;
      });

      if (_hasProject) {
        await _loadExistingBatch();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _projects = [];
        _selectedProjectId = null;
      });
    } finally {
      setState(() {
        _loadingProjects = false;
      });
    }
  }

  Future<void> _loadExistingBatch() async {
    if (!_hasProject) return;

    setState(() {
      _loadingExistingBatch = true;
      _error = null;
      _actionMessage = null;
      _generationData = null;
      _batchDetail = null;
      _batchList = [];
      _resetReviewTools();
    });

    try {
      final res = await _api.getJson(
        '/monthly-cost/batches',
        query: {
          'project_id': _selectedProjectId!.trim(),
          'cost_month': _monthValue(_selectedMonth),
          'option_type': _selectedOption,
        },
      );

      List<Map<String, dynamic>> rows = [];
      if (res is List) {
        rows = res
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (res is Map && res['data'] is List) {
        rows = (res['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      setState(() {
        _batchList = rows;
      });

      if (rows.isNotEmpty) {
        await _loadBatchDetail(
          _safe(rows.first['batch_id']),
          keepActionMessage: false,
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loadingExistingBatch = false;
      });
    }
  }

  Future<void> _loadBatchDetail(
    String batchId, {
    bool keepActionMessage = true,
  }) async {
    if (batchId.trim().isEmpty) return;

    try {
      final res = await _api.getJson('/monthly-cost/batches/$batchId');

      Map<String, dynamic>? detail;
      if (res is Map && res['data'] is Map) {
        detail = Map<String, dynamic>.from(res['data']);
      } else if (res is Map) {
        detail = Map<String, dynamic>.from(res);
      }

      if (detail == null) return;

      final Map<String, dynamic> batchNode = detail['batch'] is Map
          ? Map<String, dynamic>.from(detail['batch'] as Map)
          : <String, dynamic>{};

      setState(() {
        _batchDetail = detail;
        _generationData = batchNode;
        if (!keepActionMessage) {
          _actionMessage = null;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _validate({bool preserveGenerationData = false}) async {
    if (!_hasProject) {
      setState(() {
        _error = 'Please select a project first.';
      });
      return;
    }

    if (_isApprovedLocked) {
      setState(() {
        _error = null;
        _actionMessage = 'This monthly batch was approved by PM and is locked.';
      });
      return;
    }

    setState(() {
      _validating = true;
      _error = null;
      _actionMessage = null;
      if (!preserveGenerationData) {
        _generationData = null;
        _batchDetail = null;
        _batchList = [];
      }
    });

    try {
      final body = {
        'project_id': _selectedProjectId!.trim(),
        'cost_month': _monthValue(_selectedMonth),
        'option_type': _selectedOption,
      };

      final res = await _api.postJson('/monthly-cost/validate', body: body);

      setState(() {
        _validationData = (res is Map) ? Map<String, dynamic>.from(res) : null;
        _actionMessage = 'Validation completed.';
      });

      if (preserveGenerationData || (_validationData?['ready'] == true)) {
        await _loadExistingBatch();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _validationData = null;
      });
    } finally {
      setState(() {
        _validating = false;
      });
    }
  }

  Future<void> _generate() async {
    if (!_hasProject) {
      setState(() {
        _error = 'Please select a project first.';
      });
      return;
    }

    if (_isApprovedLocked) {
      setState(() {
        _error = null;
        _actionMessage =
            'This monthly batch was approved by PM and cannot be regenerated.';
      });
      return;
    }

    if (_validationData == null) {
      await _validate();
      if (_validationData == null) return;
    }

    final ready = _validationData?['ready'] == true;
    if (!ready) {
      _showMessage(
        'Generation Blocked',
        'Validation still has blockers. Fix them first, then generate.',
      );
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      final body = {
        'project_id': _selectedProjectId!.trim(),
        'cost_month': _monthValue(_selectedMonth),
        'option_type': _selectedOption,
      };

      final res = await _api.postJson('/monthly-cost/generate', body: body);

      setState(() {
        _generationData = (res is Map) ? Map<String, dynamic>.from(res) : null;
        _actionMessage = 'Monthly batch generated successfully.';
      });

      await _validate(preserveGenerationData: true);
      if (_currentBatchId != null) {
        await _loadBatchDetail(_currentBatchId!);
      } else {
        await _loadExistingBatch();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _generating = false;
      });
    }
  }

  Future<void> _submitBatch() async {
    final batchId = _currentBatchId;
    if (batchId == null || batchId.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      await _api.postJson('/monthly-cost/batches/$batchId/submit', body: {});
      await _loadExistingBatch();
      await _loadBatchDetail(batchId);
      setState(() {
        _actionMessage = 'Batch submitted to PM successfully.';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _approveBatch() async {
    final batchId = _currentBatchId;
    if (batchId == null || batchId.isEmpty) return;

    setState(() {
      _approving = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      await _api.postJson('/monthly-cost/batches/$batchId/approve', body: {});
      await _loadExistingBatch();
      await _loadBatchDetail(batchId);
      setState(() {
        _actionMessage = 'Batch approved successfully.';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _approving = false;
      });
    }
  }

  Future<void> _rejectBatch() async {
    final batchId = _currentBatchId;
    if (batchId == null || batchId.isEmpty) return;

    String reason = '';

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) {
            return AlertDialog(
              title: const Text('Return Batch to Cost Controller'),
              content: TextField(
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (v) => reason = v,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Write the reason for return/reject',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _rejecting = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      await _api.postJson(
        '/monthly-cost/batches/$batchId/reject',
        body: {'reason': reason.trim()},
      );
      await _loadExistingBatch();
      await _loadBatchDetail(batchId);
      setState(() {
        _actionMessage = 'Batch returned to Cost Controller.';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _rejecting = false;
      });
    }
  }

  void _showMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey.withOpacity(0.12),
              child: Icon(icon, color: Colors.black87),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSummaryCard(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workerSummaryCard(Map<String, dynamic> worker) {
    final originalMin = (worker['original_minutes'] as double?) ?? 0.0;
    final addedMin = (worker['added_minutes'] as double?) ?? 0.0;
    final adjustedMin = (worker['adjusted_minutes'] as double?) ?? 0.0;
    final differenceMin = (worker['difference_minutes'] as double?) ?? 0.0;

    final originalHr = originalMin / 60.0;
    final addedHr = addedMin / 60.0;
    final adjustedHr = adjustedMin / 60.0;
    final differenceHr = differenceMin / 60.0;

    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _safe(worker['employee_id']),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _safe(worker['employee_name']),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          _workerSummaryLine(
            'Original',
            '${originalMin.toStringAsFixed(2)} min / ${originalHr.toStringAsFixed(2)} hr',
          ),
          _workerSummaryLine(
            'Added',
            '${addedMin.toStringAsFixed(2)} min / ${addedHr.toStringAsFixed(2)} hr',
          ),
          _workerSummaryLine(
            'Adjusted',
            '${adjustedMin.toStringAsFixed(2)} min / ${adjustedHr.toStringAsFixed(2)} hr',
          ),
          _workerSummaryLine(
            'Difference',
            '${differenceMin.toStringAsFixed(2)} min / ${differenceHr.toStringAsFixed(2)} hr',
            valueStyle: TextStyle(
              color: _differenceColor(differenceMin),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _workerSummaryLine(
    String title,
    String value, {
    TextStyle? valueStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle ??
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewTools() {
    final workerOptions = _workerFilterOptions;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: _workerSearchController,
            decoration: InputDecoration(
              labelText: 'Search worker',
              hintText: 'E1001 or Worker One',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _workerSearchText.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        setState(() {
                          _workerSearchText = '';
                          _workerSearchController.clear();
                        });
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) {
              setState(() {
                _workerSearchText = value;
              });
            },
          ),
        ),
        SizedBox(
          width: 280,
          child: DropdownButtonFormField<String>(
            value: workerOptions.contains(_selectedWorkerFilter)
                ? _selectedWorkerFilter
                : 'ALL',
            decoration: const InputDecoration(
              labelText: 'Worker filter',
              border: OutlineInputBorder(),
            ),
            items: workerOptions.map((option) {
              if (option == 'ALL') {
                return const DropdownMenuItem<String>(
                  value: 'ALL',
                  child: Text('All workers'),
                );
              }
              final parts = option.split('|');
              final id = parts.isNotEmpty ? parts.first : '';
              final name = parts.length > 1 ? parts[1] : '';
              return DropdownMenuItem<String>(
                value: option,
                child: Text(name.trim().isEmpty ? id : '$id — $name'),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedWorkerFilter = value ?? 'ALL';
              });
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: OutlinedButton.icon(
            onPressed: _pickFromDate,
            icon: const Icon(Icons.date_range),
            label: Text(
              _fromDate == null ? 'From Date' : _displayDate(_fromDate),
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: OutlinedButton.icon(
            onPressed: _pickToDate,
            icon: const Icon(Icons.event),
            label: Text(
              _toDate == null ? 'To Date' : _displayDate(_toDate),
            ),
          ),
        ),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String>(
            value: _sortOption,
            decoration: const InputDecoration(
              labelText: 'Sort',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'DIFF_DESC',
                child: Text('Difference High → Low'),
              ),
              DropdownMenuItem(
                value: 'DIFF_ASC',
                child: Text('Difference Low → High'),
              ),
              DropdownMenuItem(
                value: 'DATE_ASC',
                child: Text('Date Asc'),
              ),
              DropdownMenuItem(
                value: 'DATE_DESC',
                child: Text('Date Desc'),
              ),
              DropdownMenuItem(
                value: 'WORKER',
                child: Text('Worker ID'),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _sortOption = value ?? 'DIFF_DESC';
              });
            },
          ),
        ),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _workerSearchText = '';
              _workerSearchController.clear();
              _selectedWorkerFilter = 'ALL';
              _fromDate = null;
              _toDate = null;
              _sortOption = 'DIFF_DESC';
            });
          },
          icon: const Icon(Icons.filter_alt_off),
          label: const Text('Clear Filters'),
        ),
      ],
    );
  }

  Widget _buildWorkerSummarySection() {
    final summaries = _workerSummaries;
    if (summaries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: const Text('No worker summary available for current filter.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Worker Summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade900,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: summaries.map(_workerSummaryCard).toList(),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 320,
          child: DropdownButtonFormField<String>(
            value: _hasProject ? _selectedProjectId : null,
            decoration: const InputDecoration(
              labelText: 'Project',
              border: OutlineInputBorder(),
            ),
            items: _projects.map((p) {
              final code = _safe(p['project_code']).trim();
              final name = _safe(p['project_name']).trim();
              return DropdownMenuItem<String>(
                value: code,
                child: Text(name.isEmpty ? code : '$code — $name'),
              );
            }).toList(),
            onChanged: _loadingProjects || _busy
                ? null
                : (value) async {
                    setState(() {
                      _selectedProjectId = value?.trim();
                      _validationData = null;
                      _generationData = null;
                      _batchDetail = null;
                      _batchList = [];
                      _error = null;
                      _actionMessage = null;
                      _resetReviewTools();
                    });
                    await _loadExistingBatch();
                  },
          ),
        ),
        SizedBox(
          width: 180,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _pickMonth,
            icon: const Icon(Icons.calendar_month),
            label: Text(_monthLabel(_selectedMonth)),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            value: _selectedOption,
            decoration: const InputDecoration(
              labelText: 'Option',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'OPTION1', child: Text('OPTION1')),
              DropdownMenuItem(value: 'OPTION2', child: Text('OPTION2')),
            ],
            onChanged: _busy
                ? null
                : (value) async {
                    if (value == null) return;
                    setState(() {
                      _selectedOption = value;
                      _validationData = null;
                      _generationData = null;
                      _batchDetail = null;
                      _batchList = [];
                      _error = null;
                      _actionMessage = null;
                      _resetReviewTools();
                    });
                    await _loadExistingBatch();
                  },
          ),
        ),
        ElevatedButton.icon(
          onPressed: (_busy || !_hasProject || _isApprovedLocked)
              ? null
              : _validate,
          icon: _validating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rule_folder_outlined),
          label: const Text('Validate'),
        ),
        FilledButton.icon(
          onPressed: (_busy || !_hasProject || _isApprovedLocked)
              ? null
              : _generate,
          icon: _generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add_check_circle_outlined),
          label: const Text('Generate'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  await _loadProjects();
                  await _loadExistingBatch();
                },
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _buildStateBanner() {
    if (_error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withOpacity(0.30)),
        ),
        child: Text(
          _error!,
          style: TextStyle(color: Colors.red.shade700),
        ),
      );
    }

    if (_actionMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.30)),
        ),
        child: Text(
          _actionMessage!,
          style: TextStyle(color: Colors.green.shade700),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildValidationSummary() {
    final data = _validationData;
    if (data == null) {
      return const Center(
        child: Text('Run validation to see monthly readiness.'),
      );
    }

    final counts = (data['counts'] is Map)
        ? Map<String, dynamic>.from(data['counts'])
        : <String, dynamic>{};

    final ready = data['ready'] == true;

    return Column(
      children: [
        Row(
          children: [
            _summaryCard(
              title: 'Ready',
              value: ready ? 'YES' : 'NO',
              icon: ready
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
            ),
            const SizedBox(width: 12),
            _summaryCard(
              title: 'Open Sessions',
              value: _safe(counts['open_sessions']).isEmpty
                  ? '0'
                  : _safe(counts['open_sessions']),
              icon: Icons.timelapse,
            ),
            const SizedBox(width: 12),
            _summaryCard(
              title: 'Unfinalized Days',
              value: _safe(counts['unfinalized_days']).isEmpty
                  ? '0'
                  : _safe(counts['unfinalized_days']),
              icon: Icons.event_busy,
            ),
            const SizedBox(width: 12),
            _summaryCard(
              title: 'Missing Runs',
              value: _safe(counts['missing_adjustment_runs']).isEmpty
                  ? '0'
                  : _safe(counts['missing_adjustment_runs']),
              icon: Icons.playlist_remove,
            ),
            const SizedBox(width: 12),
            _summaryCard(
              title: 'Blockers',
              value: _safe(counts['blocker_issues']).isEmpty
                  ? '0'
                  : _safe(counts['blocker_issues']),
              icon: Icons.block,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildIssuesTable()),
      ],
    );
  }

  Widget _buildIssuesTable() {
    final data = _validationData;
    final issues = (data != null && data['issues'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['issues'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    if (issues.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: const Center(
          child: Text('No validation issues found.'),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    'Type',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    'Severity',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'Date',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'Worker',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'Supervisor',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'SE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'Task',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Message',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: issues.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, i) {
                final m = issues[i];
                final severity = _safe(m['severity']).toUpperCase();
                final severityColor = severity == 'BLOCKER'
                    ? Colors.red
                    : severity == 'WARNING'
                        ? Colors.orange
                        : Colors.blue;

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 140, child: Text(_safe(m['issue_type']))),
                      SizedBox(
                        width: 90,
                        child: Text(
                          severity,
                          style: TextStyle(
                            color: severityColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: 110, child: Text(_safe(m['work_date']))),
                      SizedBox(width: 110, child: Text(_safe(m['employee_id']))),
                      SizedBox(
                        width: 110,
                        child: Text(_safe(m['supervisor_employee_id'])),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(_safe(m['se_employee_id'])),
                      ),
                      SizedBox(width: 100, child: Text(_safe(m['task_id']))),
                      Expanded(child: Text(_safe(m['message']))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final s = status.toUpperCase();
    Color fg;
    Color bg;

    switch (s) {
      case 'PM_APPROVED':
        fg = Colors.green.shade700;
        bg = Colors.green.withOpacity(0.10);
        break;
      case 'PM_RETURNED':
        fg = Colors.red.shade700;
        bg = Colors.red.withOpacity(0.10);
        break;
      case 'SUBMITTED':
        fg = Colors.blue.shade700;
        bg = Colors.blue.withOpacity(0.10);
        break;
      case 'GENERATED':
        fg = Colors.orange.shade800;
        bg = Colors.orange.withOpacity(0.10);
        break;
      default:
        fg = Colors.grey.shade800;
        bg = Colors.grey.withOpacity(0.10);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        s.isEmpty ? '-' : s,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _differenceColor(dynamic rawValue) {
    final value = rawValue is num
        ? rawValue.toDouble()
        : (double.tryParse(_safe(rawValue)) ?? 0);
    if (value > 0) return Colors.green.shade700;
    if (value < 0) return Colors.red.shade700;
    return Colors.grey.shade800;
  }

  Widget _buildReviewRowsTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('No detailed review rows available from backend yet.'),
      );
    }

    Widget headerCell(String text, double width) {
      return SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            height: 1.25,
          ),
        ),
      );
    }

    Widget dataCell(
      String text,
      double width, {
      TextStyle? style,
      TextOverflow overflow = TextOverflow.ellipsis,
    }) {
      return SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: overflow,
          style: style ?? const TextStyle(fontSize: 13),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                headerCell('Date', 110),
                headerCell('Worker', 190),
                headerCell('Project', 100),
                headerCell('Original\n(Min / Hr)', 150),
                headerCell('Added\n(Min / Hr)', 150),
                headerCell('Adjusted\n(Min / Hr)', 150),
                headerCell('Difference\n(Min / Hr)', 160),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (_, i) {
              final row = rows[i];

              final workerText =
                  '${_safe(row['employee_id'])}\n${_safe(row['employee_name'])}';

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    dataCell(_displayDate(row['work_date']), 110),
                    dataCell(workerText, 190),
                    dataCell(_safe(row['project_id']), 100),
                    dataCell(
                      '${_safe(row['original_minutes'])} / ${_safe(row['original_hours'])}',
                      150,
                    ),
                    dataCell(
                      '${_safe(row['added_minutes'])} / ${_safe(row['added_hours'])}',
                      150,
                    ),
                    dataCell(
                      '${_safe(row['adjusted_minutes'])} / ${_safe(row['adjusted_hours'])}',
                      150,
                    ),
                    dataCell(
                      '${_safe(row['difference_minutes'])} / ${_safe(row['difference_hours'])}',
                      160,
                      style: TextStyle(
                        color: _differenceColor(row['difference_minutes']),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackItemsTable(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('No batch detail items available yet.'),
      );
    }

    Widget headerCell(String text, double width) {
      return SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            height: 1.25,
          ),
        ),
      );
    }

    Widget dataCell(
      String text,
      double width, {
      TextStyle? style,
      TextOverflow overflow = TextOverflow.ellipsis,
    }) {
      return SizedBox(
        width: width,
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: overflow,
          style: style ?? const TextStyle(fontSize: 13),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                headerCell('Date', 110),
                headerCell('Worker', 220),
                headerCell('Project', 100),
                headerCell('Original\n(Min / Hr)', 160),
                headerCell('Added\n(Min / Hr)', 160),
                headerCell('Adjusted\n(Min / Hr)', 160),
                headerCell('Difference\n(Min / Hr)', 170),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (_, i) {
              final row = items[i];

              final originalMin =
                  double.tryParse(_safe(row['original_total_minutes'])) ?? 0;
              final addedMin =
                  double.tryParse(_safe(row['added_or_distributed_minutes'])) ??
                      0;
              final adjustedMin =
                  double.tryParse(_safe(row['adjusted_total_minutes'])) ?? 0;
              final differenceMin = adjustedMin - originalMin;

              final originalHr =
                  double.tryParse(_safe(row['original_hours'])) ??
                      (originalMin / 60.0);
              final addedHr =
                  double.tryParse(_safe(row['added_hours'])) ??
                      (addedMin / 60.0);
              final adjustedHr =
                  double.tryParse(_safe(row['adjusted_hours'])) ??
                      (adjustedMin / 60.0);
              final differenceHr = adjustedHr - originalHr;

              final workerText =
                  '${_safe(row['employee_id'])}\n${_safe(row['employee_name'])}';

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    dataCell(_displayDate(row['work_date']), 110),
                    dataCell(workerText, 220),
                    dataCell(_safe(row['project_id']), 100),
                    dataCell(
                      '${originalMin.toStringAsFixed(2)} / ${originalHr.toStringAsFixed(2)}',
                      160,
                    ),
                    dataCell(
                      '${addedMin.toStringAsFixed(2)} / ${addedHr.toStringAsFixed(2)}',
                      160,
                    ),
                    dataCell(
                      '${adjustedMin.toStringAsFixed(2)} / ${adjustedHr.toStringAsFixed(2)}',
                      160,
                    ),
                    dataCell(
                      '${differenceMin.toStringAsFixed(2)} / ${differenceHr.toStringAsFixed(2)}',
                      170,
                      style: TextStyle(
                        color: _differenceColor(differenceMin),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedSummary() {
    final data = _generationData;
    final detail = _batchDetail;
    final batchNode = detail != null && detail['batch'] is Map
        ? Map<String, dynamic>.from(detail['batch'] as Map)
        : null;
    final totals = detail != null && detail['totals'] is Map
        ? Map<String, dynamic>.from(detail['totals'] as Map)
        : <String, dynamic>{};
    final history = detail != null && detail['history'] is List
        ? List<Map<String, dynamic>>.from(
            (detail['history'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    final usingReviewRows = _reviewRows.isNotEmpty;
    final reviewRows = _filteredReviewRows;
    final items = _filteredFallbackItems;
    final filteredRows = usingReviewRows ? reviewRows : items;
    final filteredTotals = _filteredDetailTotals(
      usingReviewRows: usingReviewRows,
      rows: filteredRows,
    );

    if (data == null && batchNode == null) {
      if (_loadingExistingBatch) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(
        child: Text('No monthly batch generated yet.'),
      );
    }

    final role = context.read<AppState>().role.toUpperCase().trim();
    final status = _currentBatchStatus;
    final current = batchNode != null
        ? Map<String, dynamic>.from(batchNode)
        : Map<String, dynamic>.from(data!);

    final canSubmit = role == 'COST_CONTROLLER' &&
        (status == 'GENERATED' || status == 'PM_RETURNED');
    final canApproveReject = role == 'PM' && status == 'SUBMITTED';

    final detailRowCount = filteredRows.length.toString();

    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1500),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Icon(
                  status == 'PM_APPROVED'
                      ? Icons.check_circle
                      : status == 'PM_RETURNED'
                          ? Icons.cancel
                          : status == 'SUBMITTED'
                              ? Icons.forward_to_inbox
                              : Icons.hourglass_bottom,
                  size: 48,
                  color: status == 'PM_APPROVED'
                      ? Colors.green
                      : status == 'PM_RETURNED'
                          ? Colors.red
                          : status == 'SUBMITTED'
                              ? Colors.blue
                              : Colors.orange,
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Monthly Cost Batch',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: _buildStatusChip(status)),
              const SizedBox(height: 18),
              if (_isApprovedLocked)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withOpacity(0.20)),
                  ),
                  child: Text(
                    'This monthly batch was approved by PM and is now locked. Validation and regeneration are disabled.',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (role == 'COST_CONTROLLER' && !_isApprovedLocked)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withOpacity(0.18)),
                  ),
                  child: Text(
                    status == 'PM_RETURNED'
                        ? 'PM returned this batch. Please review the reason below, fix if needed, then regenerate and submit again.'
                        : status == 'SUBMITTED'
                            ? 'This batch is waiting for PM review.'
                            : 'This batch is ready for the Cost Controller workflow.',
                    style: TextStyle(color: Colors.blue.shade800),
                  ),
                ),
              Wrap(
                runSpacing: 8,
                spacing: 24,
                children: [
                  SizedBox(
                    width: 380,
                    child: _kv('Batch ID', _safe(current['batch_id'])),
                  ),
                  SizedBox(
                    width: 200,
                    child: _kv('Project', _safe(current['project_id'])),
                  ),
                  SizedBox(
                    width: 180,
                    child:
                        _kv('Month', _displayBatchMonth(current['cost_month'])),
                  ),
                  SizedBox(
                    width: 180,
                    child: _kv(
                      'Option',
                      _safe(current['option_type']).replaceAll('_', ' '),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: _kv(
                      'Inserted Items',
                      _safe(current['inserted_count'] ?? current['item_count']),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Generated By', _safe(current['generated_by'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Generated At', _safe(current['generated_at'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Submitted By', _safe(current['submitted_by'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Submitted At', _safe(current['submitted_at'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Approved By', _safe(current['approved_by'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Approved At', _safe(current['approved_at'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Returned By', _safe(current['returned_by'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Returned At', _safe(current['returned_at'])),
                  ),
                ],
              ),
              if (_safe(current['return_reason']).isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PM Return Reason',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(_safe(current['return_reason'])),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  _summaryCard(
                    title: 'Item Count',
                    value: _safe(totals['item_count']),
                    icon: Icons.format_list_numbered,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    title: 'Original',
                    value:
                        '${_safe(totals['original_total_minutes'])} min\n${_safe(totals['original_total_hours']).isNotEmpty ? _safe(totals['original_total_hours']) : _minutesToHoursText(totals['original_total_minutes'])} hr',
                    icon: Icons.timer_outlined,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    title: 'Added/Distributed',
                    value:
                        '${_safe(totals['added_or_distributed_minutes'])} min\n${_safe(totals['added_total_hours']).isNotEmpty ? _safe(totals['added_total_hours']) : _minutesToHoursText(totals['added_or_distributed_minutes'])} hr',
                    icon: Icons.auto_fix_high,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    title: 'Adjusted',
                    value:
                        '${_safe(totals['adjusted_total_minutes'])} min\n${_safe(totals['adjusted_total_hours']).isNotEmpty ? _safe(totals['adjusted_total_hours']) : _minutesToHoursText(totals['adjusted_total_minutes'])} hr',
                    icon: Icons.fact_check_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        (_exporting || (_batchDetail == null && _generationData == null))
                            ? null
                            : _exportToExcel,
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Export Excel'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        (_exporting || (_batchDetail == null && _generationData == null))
                            ? null
                            : _printPdf,
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print),
                    label: Text(kIsWeb ? 'Print / PDF' : 'Download PDF'),
                  ),
                  if (canSubmit)
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _submitBatch,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.forward_to_inbox),
                      label: const Text('Submit to PM'),
                    ),
                  if (canApproveReject)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: _approving ? null : _approveBatch,
                      icon: _approving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
                  if (canApproveReject)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: _rejecting ? null : _rejectBatch,
                      icon: _rejecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.reply),
                      label: const Text('Return to Cost Controller'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _buildReviewTools(),
              const SizedBox(height: 20),
              _buildWorkerSummarySection(),
              const SizedBox(height: 24),
              Text(
                'Batch Review Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _detailSummaryCard(
                    'Detail Rows',
                    detailRowCount,
                  ),
                  const SizedBox(width: 12),
                  _detailSummaryCard(
                    'Original Hours',
                    _hoursFromMinutes(filteredTotals['original_minutes'] ?? 0.0),
                  ),
                  const SizedBox(width: 12),
                  _detailSummaryCard(
                    'Added Hours',
                    _hoursFromMinutes(filteredTotals['added_minutes'] ?? 0.0),
                  ),
                  const SizedBox(width: 12),
                  _detailSummaryCard(
                    'Adjusted Hours',
                    _hoursFromMinutes(filteredTotals['adjusted_minutes'] ?? 0.0),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_reviewRows.isNotEmpty)
                _buildReviewRowsTable(reviewRows)
              else
                _buildFallbackItemsTable(items),
              const SizedBox(height: 24),
              Text(
                'Batch History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 10),
              if (history.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('No history available yet.'),
                )
              else
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black.withOpacity(0.05)),
                  ),
                  child: Column(
                    children: history.map((h) {
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(_safe(h['action'])),
                        subtitle: Text(
                          '${_safe(h['actor_id'])} • ${_safe(h['created_at'])}'
                          '${_safe(h['comments']).isNotEmpty ? '\n${_safe(h['comments'])}' : ''}',
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          Flexible(
            child: SelectableText(
              v.isEmpty ? '-' : v,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppState>().role.toUpperCase().trim();

    if (!['COST_CONTROLLER', 'PM', 'ADMIN'].contains(role)) {
      return const Center(
        child: Text(
          'This page is available only for Cost Controller, PM, and Admin.',
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Monthly Cost Batch'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Validation'),
              Tab(text: 'Generated Batch'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildFilters(),
              const SizedBox(height: 12),
              _buildStateBanner(),
              if (_error != null || _actionMessage != null)
                const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildValidationSummary(),
                    _buildGeneratedSummary(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // ✅ ADD THESE HERE (just before last })
  pw.Widget _th(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _tc(String text, {bool isNumber = false, bool alignLeft = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10),
        textAlign: isNumber
            ? pw.TextAlign.right
            : (alignLeft ? pw.TextAlign.left : pw.TextAlign.center),
      ),
    );
  }

}