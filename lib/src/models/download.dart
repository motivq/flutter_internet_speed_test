class Download {
  final double length;
  final int packetLength;

  Download({
    required this.length,
    required this.packetLength,
  });

  factory Download.fromJson(Map<String, dynamic> json) {
    return Download(
      length: double.parse(json['testlength']),
      packetLength: int.parse(json['packetlength']),
    );
  }
}
