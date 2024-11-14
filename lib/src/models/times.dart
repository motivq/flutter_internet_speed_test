class Times {
  final int downloadOne;
  final int downloadTwo;
  final int downloadThree;
  final int uploadOne;
  final int uploadTwo;
  final int uploadThree;

  Times({
    required this.downloadOne,
    required this.downloadTwo,
    required this.downloadThree,
    required this.uploadOne,
    required this.uploadTwo,
    required this.uploadThree,
  });

  factory Times.fromJson(Map<String, dynamic> json) {
    return Times(
      downloadOne: int.parse(json['dl1'] as String),
      downloadTwo: int.parse(json['dl2'] as String),
      downloadThree: int.parse(json['dl3'] as String),
      uploadOne: int.parse(json['ul1'] as String),
      uploadTwo: int.parse(json['ul2'] as String),
      uploadThree: int.parse(json['ul3'] as String),
    );
  }
}
