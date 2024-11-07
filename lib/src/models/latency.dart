class Latency {
  final double length;

  Latency({
    required this.length,
  });

  factory Latency.fromJson(Map<String, dynamic> json) {
    return Latency(
      length: double.parse(json['testlength']),
    );
  }
}
