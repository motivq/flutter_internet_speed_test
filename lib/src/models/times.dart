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
      downloadOne: int.parse(json['dl1']),
      downloadTwo: int.parse(json['dl2']),
      downloadThree: int.parse(json['dl3']),
      uploadOne: int.parse(json['ul1']),
      uploadTwo: int.parse(json['ul2']),
      uploadThree: int.parse(json['ul3']),
    );
  }
}
