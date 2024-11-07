import 'client.dart';
import 'download.dart';
import 'latency.dart';
import 'server_config.dart';
import 'times.dart';
import 'upload.dart';

class Configuration {
  final Client client;
  final ServerConfig serverConfig;
  final Times times;
  final Download download;
  final Upload upload;
  final Latency latency;

  Configuration({
    required this.client,
    required this.serverConfig,
    required this.times,
    required this.download,
    required this.upload,
    required this.latency,
  });

  factory Configuration.fromJson(Map<String, dynamic> json) {
    return Configuration(
      client: Client.fromJson(json['client']),
      serverConfig: ServerConfig.fromJson(json['server-config']),
      times: Times.fromJson(json['times']),
      download: Download.fromJson(json['socket-download']),
      upload: Upload.fromJson(json['socket-upload']),
      latency: Latency.fromJson(json['socket-latency']),
    );
  }
}
