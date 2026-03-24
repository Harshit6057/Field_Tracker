import 'dart:typed_data';

enum VisitEvidenceType { place, person }

class VisitEvidence {
  const VisitEvidence({
    required this.id,
    required this.employeeId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.locationName,
    required this.remarks,
    required this.type,
    this.photoUrl,
    this.localPhotoBytes,
  });

  final String id;
  final String employeeId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String locationName;
  final String remarks;
  final VisitEvidenceType type;
  final String? photoUrl;
  final Uint8List? localPhotoBytes;

  String get typeLabel => type == VisitEvidenceType.place ? 'Place' : 'Person';
}