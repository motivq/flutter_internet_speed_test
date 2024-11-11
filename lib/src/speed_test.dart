import 'dart:js';

abstract class ISpeedtest {
  void setParameter(String key, dynamic value);
  dynamic getState();
  dynamic getTestPoints();
  dynamic getSelectedServer();
  void addTestPoints(dynamic points);
  void addTestPoint(dynamic point);
  void setSelectedServer(dynamic server);
  void getIp(Function callback);
  void startDownloadTest();
  void startUploadTest();
  void callMethod(String method, [List<dynamic>? args]);
  void reset([bool softReset]);
  void abort();
  void on(String event, Function callback);
  void onUpdate(Function callback);
  void onEnd(Function callback);
}

class JsSpeedtest implements ISpeedtest {
  final JsObject _jsObject;

  JsSpeedtest(this._jsObject);

  @override
  void setParameter(String key, dynamic value) {
    _jsObject.callMethod('setParameter', [key, value]);
  }

  @override
  dynamic getState() {
    return _jsObject.callMethod('getState');
  }

  @override
  dynamic getTestPoints() {
    return _jsObject.callMethod('getTestPoints');
  }

  @override
  dynamic getSelectedServer() {
    return _jsObject.callMethod('getSelectedServer');
  }

  @override
  void addTestPoints(dynamic points) {
    _jsObject.callMethod('addTestPoints', [points]);
  }

  @override
  void addTestPoint(dynamic point) {
    _jsObject.callMethod('addTestPoint', [point]);
  }

  @override
  void setSelectedServer(dynamic server) {
    _jsObject.callMethod('setSelectedServer', [server]);
  }

  @override
  void getIp(Function callback) {
    _jsObject.callMethod('getIp', [allowInterop(callback)]);
  }

  @override
  void startDownloadTest() {
    _jsObject.callMethod('startDownloadTest');
  }

  @override
  void startUploadTest() {
    _jsObject.callMethod('startUploadTest');
  }

  @override
  void callMethod(String method, [List<dynamic>? args]) {
    _jsObject.callMethod(method, args);
  }

  @override
  void reset([bool softReset = false]) {
    _jsObject.callMethod('reset', [softReset]);
  }

  @override
  void abort() {
    _jsObject.callMethod('abort');
  }

  @override
  void on(String event, Function callback) {
    _jsObject.callMethod('on', [event, allowInterop(callback)]);
  }

  @override
  void onUpdate(Function callback) {
    _jsObject['onupdate'] = allowInterop(callback);
  }

  @override
  void onEnd(Function callback) {
    _jsObject['onend'] = allowInterop(callback);
  }
}
