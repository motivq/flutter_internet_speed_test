class Location {
  late final String? city;
  late final String? country;

  Location({this.city, this.country});

  Location.fromJson(Map<String, dynamic> json) {
    city = json['city'] as String?;
    country = json['country'] as String?;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['city'] = city;
    data['country'] = country;
    return data;
  }
}
