import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/tracking_analytics.dart';

class ExportedTrackingFile {
  const ExportedTrackingFile({required this.path, required this.fileName});

  final String path;
  final String fileName;
}

class TrackingExportService {
  Future<ExportedTrackingFile> exportDailyReportCsv(
    DailyTrackingReport report,
  ) async {
    final buffer = StringBuffer();
    final dateFmt = DateFormat('yyyy-MM-dd hh:mm:ss a');

    buffer.writeln(
      'employee_id,employee_name,date,total_distance_meters,active_duration_minutes,total_points',
    );
    buffer.writeln(
      '${_csv(report.employeeId)},${_csv(report.employeeName)},${DateFormat('yyyy-MM-dd').format(report.date)},${report.totalDistanceMeters.toStringAsFixed(2)},${report.activeDuration.inMinutes},${report.points.length}',
    );

    buffer.writeln();
    buffer.writeln(
      'dwell_start,dwell_end,dwell_duration_minutes,center_latitude,center_longitude,zone_name',
    );
    for (final dwell in report.dwellPeriods) {
      buffer.writeln(
        '${dateFmt.format(dwell.startTime)},${dateFmt.format(dwell.endTime)},${dwell.duration.inMinutes},${dwell.centerLatitude.toStringAsFixed(6)},${dwell.centerLongitude.toStringAsFixed(6)},${_csv(dwell.zoneName ?? 'Unknown')}',
      );
    }

    buffer.writeln();
    buffer.writeln('point_timestamp,latitude,longitude,speed_mps');
    for (final point in report.points) {
      buffer.writeln(
        '${dateFmt.format(point.timestamp)},${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)},${point.speedMetersPerSecond?.toStringAsFixed(2) ?? ''}',
      );
    }

    final fileName =
        'tracking_${report.employeeId}_${DateFormat('yyyyMMdd').format(report.date)}.csv';
    final file = await _writeFile(fileName, buffer.toString());
    return ExportedTrackingFile(path: file.path, fileName: fileName);
  }

  Future<ExportedTrackingFile> exportDailyReportPdf(
    DailyTrackingReport report,
  ) async {
    final document = pw.Document();
    final dateFmt = DateFormat('dd MMM yyyy');
    final timeFmt = DateFormat('hh:mm:ss a');

    document.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Daily Tracking Report'),
          pw.Text('Employee: ${report.employeeName} (${report.employeeId})'),
          pw.Text('Date: ${dateFmt.format(report.date)}'),
          pw.SizedBox(height: 8),
          pw.Bullet(
            text:
                'Total distance: ${(report.totalDistanceMeters / 1000).toStringAsFixed(2)} km',
          ),
          pw.Bullet(
            text: 'Active duration: ${report.activeDuration.inMinutes} minutes',
          ),
          pw.Bullet(text: 'Total route points: ${report.points.length}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Dwell Periods',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (report.dwellPeriods.isEmpty)
            pw.Text('No dwell periods detected.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Start', 'End', 'Duration (min)', 'Zone'],
              data: report.dwellPeriods
                  .map(
                    (dwell) => [
                      timeFmt.format(dwell.startTime),
                      timeFmt.format(dwell.endTime),
                      dwell.duration.inMinutes.toString(),
                      dwell.zoneName ?? 'Unknown',
                    ],
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );

    final fileName =
        'tracking_${report.employeeId}_${DateFormat('yyyyMMdd').format(report.date)}.pdf';
    final bytes = await document.save();
    final file = await _writeBytes(fileName, bytes);
    return ExportedTrackingFile(path: file.path, fileName: fileName);
  }

  Future<File> _writeFile(String fileName, String content) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    return file.writeAsString(content, flush: true);
  }

  Future<File> _writeBytes(String fileName, List<int> bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    return file.writeAsBytes(bytes, flush: true);
  }

  String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
