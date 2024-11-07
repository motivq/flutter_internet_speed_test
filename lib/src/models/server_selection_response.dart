import 'client.dart';
import 'location.dart';
import 'server.dart';

class ServerSelectionResponse {
  late final Client? client;
  late final List<Targets>? targets;

  ServerSelectionResponse({this.client, this.targets});

  ServerSelectionResponse.fromJson(Map<String, dynamic> json) {
    client = json['client'] != null ? Client.fromJson(json['client']) : null;
    targets = <Targets>[];
    if (json['targets'] != null) {
      json['targets'].forEach((v) {
        targets!.add(Targets.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (client != null) {
      data['client'] = client!.toJson();
    }
    if (targets != null) {
      data['targets'] = targets!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class Targets {
  late final String? name;
  late final String? url;
  late final Location? location;

  Targets({this.name, this.url, this.location});

  static Targets fromServer(Server server) {
    return Targets(
      name: server.name, // Assuming Server has a name property
      url: server.url, // Assuming Server has a url property
      location: Location.fromJson(server.location as Map<String, dynamic>),
    );
  }

  Targets.fromJson(Map<String, dynamic> json) {
    name = json['name'];
    url = json['url'];
    location =
        json['location'] != null ? Location.fromJson(json['location']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['url'] = url;
    if (location != null) {
      data['location'] = location!.toJson();
    }
    return data;
  }
}
