class Server {
  final String cc;
  final String country;
  final int id;
  final double latitude;
  final double longitude;
  final String name;
  final String sponsor;
  final String url;
  final String? url2;
  final String host;
  final double? distance;
  final Duration? latency;

  Server({
    required this.cc,
    required this.country,
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.sponsor,
    required this.url,
    this.url2,
    required this.host,
    this.distance,
    this.latency,
  });

  String get location => '$name, $country ($cc)';

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      cc: json['cc'] as String,
      country: json['country'] as String,
      id: int.parse(json['id']),
      latitude: double.parse(json['lat']),
      longitude: double.parse(json['lon']),
      name: json['name'] as String,
      sponsor: json['sponsor'] as String,
      url: json['url'] as String,
      url2: json['url2'] as String?,
      host: json['host'] as String,
      distance:
          json.containsKey('distance') ? double.parse(json['distance']) : null,
      latency: json.containsKey('latency')
          ? Duration(milliseconds: int.parse(json['latency']))
          : null,
    );
  }

  Server copyWith({Duration? latency}) {
    return Server(
      cc: cc,
      country: country,
      id: id,
      latitude: latitude,
      longitude: longitude,
      name: name,
      sponsor: sponsor,
      url: url,
      url2: url2,
      host: host,
      distance: distance,
      latency: latency ?? this.latency,
    );
  }
}
