import 'dart:convert';

class OllamaModel {
  final String name;
  final String? model;
  final int? size;
  final String? digest;
  final Map<String, dynamic>? details;
  final DateTime? expiresAt;
  final int? sizeVram;
  final int? contextLength;
  final String? detailsPretty;
  final String? modifiedAt;

  OllamaModel({
    required this.name,
    this.model,
    this.size,
    this.digest,
    this.details,
    this.expiresAt,
    this.sizeVram,
    this.contextLength,
    this.detailsPretty,
    this.modifiedAt,
  });

  factory OllamaModel.fromJson(Map<String, dynamic> json) {
    String? pretty;
    if (json['details'] is Map) {
      try {
        pretty = const JsonEncoder.withIndent('  ').convert(json['details']);
      } catch (_) {
        pretty = json['details'].toString();
      }
    }
    return OllamaModel(
      name:
          json['name'] ??
          json['model'] ??
          json['id'] ??
          json['tag'] ??
          json['title'] ??
          'Unknown',
      model: json['model'],
      size: json['size'],
      digest: json['digest'],
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'])
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'])
          : null,
      sizeVram: json['size_vram'],
      contextLength: json['context_length'],
      detailsPretty: pretty,
      modifiedAt: json['modified_at']?.toString(),
    );
  }

  String get displayName => name;

  String? get parameterSize => details?['parameter_size'];
  String? get quantizationLevel => details?['quantization_level'];
}

class RunningModel {
  final String name;
  final String? parameterSize;
  final String? quantizationLevel;
  final int? size;
  final int? sizeVram;
  final int? contextLength;

  RunningModel({
    required this.name,
    this.parameterSize,
    this.quantizationLevel,
    this.size,
    this.sizeVram,
    this.contextLength,
  });

  factory RunningModel.fromJson(Map<String, dynamic> json) {
    final details = json['details'] as Map<String, dynamic>?;
    return RunningModel(
      name: json['name'] ?? json['model'] ?? 'Unknown',
      parameterSize: details?['parameter_size'],
      quantizationLevel: details?['quantization_level'],
      size: json['size'],
      sizeVram: json['size_vram'],
      contextLength: json['context_length'],
    );
  }

  String formatDetails(String Function(dynamic) humanSize) {
    final parts = <String>[name];

    if (parameterSize != null) parts.add(parameterSize!);
    if (quantizationLevel != null) parts.add(quantizationLevel!);
    if (size != null) parts.add(humanSize(size));
    if (sizeVram != null) parts.add('VRAM: ${humanSize(sizeVram)}');
    if (contextLength != null) parts.add('CTX: $contextLength');

    return parts.join(' • ');
  }
}
