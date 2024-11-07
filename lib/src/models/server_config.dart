class ServerConfig {
  final String ignoreIds;
  final String threadCount;

  ServerConfig({
    required this.ignoreIds,
    required this.threadCount,
  });

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      ignoreIds: json['ignoreids'] as String,
      threadCount: json['threadcount'] as String,
    );
  }
}
