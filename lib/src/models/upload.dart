class Upload {
  final double length;
  final int packetLength;

  Upload({
    required this.length,
    required this.packetLength,
  });

  factory Upload.fromJson(Map<String, dynamic> json) {
    return Upload(
      length: double.parse(json['testlength'] as String),
      packetLength: int.parse(json['packetlength'] as String),
    );
  }
}
