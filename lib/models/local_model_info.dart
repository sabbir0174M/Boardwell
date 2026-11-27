class LocalModelInfo {
  const LocalModelInfo({
    required this.id,
    required this.displayName,
    required this.filePath,
    required this.sourceUrl,
    required this.sizeBytes,
    required this.installedAtMs,
    this.isActive = false,
  });

  final String id;
  final String displayName;
  final String filePath;
  final String sourceUrl;
  final int sizeBytes;
  final int installedAtMs;
  final bool isActive;

  String get formattedSize {
    if (sizeBytes <= 0) return 'External file';
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  LocalModelInfo copyWith({
    String? id,
    String? displayName,
    String? filePath,
    String? sourceUrl,
    int? sizeBytes,
    int? installedAtMs,
    bool? isActive,
  }) {
    return LocalModelInfo(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      filePath: filePath ?? this.filePath,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      installedAtMs: installedAtMs ?? this.installedAtMs,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'filePath': filePath,
      'sourceUrl': sourceUrl,
      'sizeBytes': sizeBytes,
      'installedAtMs': installedAtMs,
      'isActive': isActive ? 1 : 0,
    };
  }

  factory LocalModelInfo.fromMap(Map<String, dynamic> map) {
    return LocalModelInfo(
      id: map['id'] as String,
      displayName: map['displayName'] as String? ?? 'Local Model',
      filePath: map['filePath'] as String? ?? '',
      sourceUrl: map['sourceUrl'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      installedAtMs: (map['installedAtMs'] as num?)?.toInt() ?? 0,
      isActive: (map['isActive'] == 1 || map['isActive'] == true),
    );
  }
}

class SuggestedModelCatalogItem {
  const SuggestedModelCatalogItem({
    required this.id,
    required this.name,
    required this.description,
    required this.estimatedSizeLabel,
    required this.minRamGb,
    required this.defaultDownloadUrl,
  });

  final String id;
  final String name;
  final String description;
  final String estimatedSizeLabel;
  final double minRamGb;
  final String defaultDownloadUrl;

  /// Editable starter suggestions — users can modify URLs or import any future .task / .bin file.
  static const List<SuggestedModelCatalogItem> starterCatalog = [
    SuggestedModelCatalogItem(
      id: 'gemma3_1b_it_task',
      name: 'Gemma 3 1B Instruct (.task)',
      description: 'Compact 4-bit MediaPipe model for fast offline chess coaching.',
      estimatedSizeLabel: '~550 MB',
      minRamGb: 4.0,
      defaultDownloadUrl:
          'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    ),
    SuggestedModelCatalogItem(
      id: 'gemma2_2b_it_task',
      name: 'Gemma 2 2B Instruct (.task)',
      description: 'Richer tactical explanations for 6 GB+ 64-bit devices.',
      estimatedSizeLabel: '~1.3 GB',
      minRamGb: 6.0,
      defaultDownloadUrl:
          'https://huggingface.co/litert-community/Gemma2-2B-IT/resolve/main/gemma2-2b-it-cpu-int8.task',
    ),
  ];
}
