enum TestType {
  download,
  upload,
  ping,
}

enum CallbacksEnum {
  startDownLoadTesting,
  startUploadTesting,
  startLatencyTesting,
}

enum ListenerEnum {
  complete,
  error,
  progress,
  cancel,
}

enum SpeedUnit {
  kbps,
  mbps,
  ms,
}
