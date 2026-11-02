import 'msp_descriptors.dart';

export 'msp_descriptors.dart';

class MspManifest {
  MspManifest();

  factory MspManifest.fromJson(Map<String, Object?> json) {
    final MspManifest manifest = MspManifest()
      ..version = json['version'] as int? ?? 0;
    manifest.patterns.addAll(_readStrings(json['patterns']));
    manifest.capabilities.addAll(_readStrings(json['capabilities']));
    manifest.signals.addAll(_readSignals(json['signals']));
    manifest.tools.addAll(_readTools(json['tools']));
    return manifest;
  }

  int version = 0;
  final List<String> patterns = <String>[];
  final Set<String> capabilities = <String>{};
  final List<MspSignalDescriptor> signals = <MspSignalDescriptor>[];
  final List<MspToolDescriptor> tools = <MspToolDescriptor>[];

  void addTool(MspToolDescriptor descriptor) {
    tools.removeWhere((MspToolDescriptor item) => item.name == descriptor.name);
    tools.add(descriptor);
    version++;
  }

  void addSignal(MspSignalDescriptor descriptor) {
    signals.removeWhere(
        (MspSignalDescriptor item) => item.path == descriptor.path);
    signals.add(descriptor);
    version++;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'patterns': List<String>.of(patterns),
        'patternMetadata': <String, Object?>{},
        'capabilities': capabilities.toList()..sort(),
        'signals':
            signals.map((MspSignalDescriptor item) => item.toJson()).toList(),
        'tools': tools.map((MspToolDescriptor item) => item.toJson()).toList(),
        'resources': <Object?>[],
        'prompts': <Object?>[],
        'clientCapabilities': <String, Object?>{
          'sampling': false,
          'elicitation': false,
          'roots': false,
        },
      };
}

List<String> _readStrings(Object? value) {
  if (value is! List) return <String>[];
  return value.whereType<String>().toList();
}

List<MspSignalDescriptor> _readSignals(Object? value) {
  if (value is! List) return <MspSignalDescriptor>[];
  return value
      .whereType<Map<String, Object?>>()
      .map(MspSignalDescriptor.fromJson)
      .toList();
}

List<MspToolDescriptor> _readTools(Object? value) {
  if (value is! List) return <MspToolDescriptor>[];
  return value
      .whereType<Map<String, Object?>>()
      .map(MspToolDescriptor.fromJson)
      .toList();
}
