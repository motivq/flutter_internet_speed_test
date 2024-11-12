import 'location.dart';

class Client {
  late final String ip;
  late final String isp;
  late final double latitude;
  late final double longitude;
  late final String? asn;
  late final Location? location;

  // Additional fields from the new model
  late final String city;
  late final String country;
  late final String hostname;
  late final String loc;
  late final String org;
  late final String postal;
  late final String region;
  late final String timezone;

  Client({
    required this.ip,
    required this.isp,
    required this.latitude,
    required this.longitude,
    this.asn,
    this.location,
    // Initialize additional fields
    this.city = '',
    this.country = '',
    this.hostname = '',
    this.loc = '',
    this.org = '',
    this.postal = '',
    this.region = '',
    this.timezone = '',
  });

  Client.fromJson(Map<String, dynamic> json) {
    ip = json['ip'] as String;
    isp = json['isp'] as String;
    latitude = double.parse((json['lat']?.toString() ?? '0.0'));
    longitude = double.parse((json['lon']?.toString() ?? '0.0'));
    asn = json['asn'];
    location =
        json['location'] != null ? Location.fromJson(json['location']) : null;
    // Parse additional fields
    city = json['city'] ?? '';
    country = json['country'] ?? '';
    hostname = json['hostname'] ?? '';
    loc = json['loc'] ?? '';
    org = json['org'] ?? '';
    postal = json['postal'] ?? '';
    region = json['region'] ?? '';
    timezone = json['timezone'] ?? '';
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
    // Add additional fields
    data['city'] = city;
    data['country'] = country;
    data['hostname'] = hostname;
    data['loc'] = loc;
    data['org'] = org;
    data['postal'] = postal;
    data['region'] = region;
    data['timezone'] = timezone;
    return data;
  }

  // Factory constructor to create a Client from the new model
  factory Client.fromNewModel(Map<String, dynamic> json) {
    return Client(
      ip: json['ip'],
      isp: json['org'], // Assuming 'org' is equivalent to 'isp'
      latitude: double.parse(json['latitude']),
      longitude: double.parse(json['longitude']),
      asn: null, // Assuming ASN is not available in the new model
      location: null, // Assuming Location is not available in the new model
      // Initialize additional fields
      city: json['city'] ?? '',
      country: json['country'] ?? '',
      hostname: json['hostname'] ?? '',
      loc: json['loc'] ?? '',
      org: json['org'] ?? '',
      postal: json['postal'] ?? '',
      region: json['region'] ?? '',
      timezone: json['timezone'] ?? '',
    );
  }

  // Method to convert the existing Client to the new model
  Map<String, dynamic> toNewModel() {
    return {
      'city': city,
      'country': country,
      'hostname': hostname,
      'ip': ip,
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'loc': loc,
      'org': isp,
      'postal': postal,
      'region': region,
      'timezone': timezone,
    };
  }
}
