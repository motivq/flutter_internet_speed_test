import 'server.dart';

class Servers {
  final List<Server> servers;

  Servers({required this.servers});

  factory Servers.fromJson(Map<String, dynamic> json) {
    var serverList = <Server>[];
    if (json['servers'] is List) {
      serverList = (json['servers'] as List)
          .map((serverJson) =>
              Server.fromJson(serverJson as Map<String, dynamic>))
          .toList();
    } else if (json['servers'] is Map) {
      // Handle XML to JSON conversion where 'servers' might contain 'server' key
      var serversJson = json['servers']['server'] as List;
      serverList = serversJson
          .map((serverJson) =>
              Server.fromJson(serverJson as Map<String, dynamic>))
          .toList();
    }
    return Servers(servers: serverList);
  }
}
