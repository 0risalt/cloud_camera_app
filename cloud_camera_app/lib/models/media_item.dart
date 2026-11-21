class MediaItem {
  final String id;
  final String localPath;
  String? cloudUrl;
  String? publicId;
  final bool isVideo;
  final DateTime createdAt;
  bool isFavorite;
  UploadStatus status;

  MediaItem({
    required this.id,
    required this.localPath,
    this.cloudUrl,
    this.publicId,
    required this.isVideo,
    required this.createdAt,
    this.isFavorite = false,
    this.status = UploadStatus.pending,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'localPath': localPath,
        'cloudUrl': cloudUrl,
        'publicId': publicId,
        'isVideo': isVideo,
        'createdAt': createdAt.toIso8601String(),
        'isFavorite': isFavorite,
      };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'],
        localPath: json['localPath'],
        cloudUrl: json['cloudUrl'],
        publicId: json['publicId'],
        isVideo: json['isVideo'],
        createdAt: DateTime.parse(json['createdAt']),
        isFavorite: json['isFavorite'] ?? false,
        status: json['cloudUrl'] != null
            ? UploadStatus.uploaded
            : UploadStatus.pending,
      );
}

enum UploadStatus { pending, uploading, uploaded, failed }
