class Location {
  late final String? city;
  late final String? country;

  Location({this.city, this.country});

  Location.fromJson(Map<String, dynamic> json) {
    city = json['city'];
    country = json['country'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['city'] = city;
    data['country'] = country;
    return data;
  }
}
