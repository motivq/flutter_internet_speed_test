import 'location.dart';

class Client {
  late final String ip;
  late final String isp;
  late final double latitude;
  late final double longitude;
  late final String? asn;
  late final Location? location;

  Client({
    required this.ip,
    required this.isp,
    required this.latitude,
    required this.longitude,
    this.asn,
    this.location,
  });

  Client.fromJson(Map<String, dynamic> json) {
    ip = json['ip'] as String;
    isp = json['isp'] as String;
    latitude = double.parse((json['lat']?.toString() ?? '0.0'));
    longitude = double.parse((json['lon']?.toString() ?? '0.0'));
    asn = json['asn'];
    location =
        json['location'] != null ? Location.fromJson(json['location']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['ip'] = ip;
    data['isp'] = isp;
    data['lat'] = latitude.toString();
    data['lon'] = longitude.toString();
    data['asn'] = asn;
    if (location != null) {
      data['location'] = location!.toJson();
    }
    return data;
  }
}
