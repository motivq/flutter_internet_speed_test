/*
	LibreSpeed - Main2
	by Federico Dossena
	https://github.com/librespeed/speedtest/
	GNU LGPLv3 License
*/

/*
   This is the main interface between your webpage and the speedtest.
   It hides the speedtest web worker to the page, and provides many convenient functions to control the test.
   
   The best way to learn how to use this is to look at the basic example, but here's some documentation.
  
   To initialize the test, create a new Speedtest object:
    var s=new Speedtest();
   Now you can think of this as a finite state machine. These are the states (use getState() to see them):
   - 0: here you can change the speedtest settings (such as test duration) with the setParameter("parameter",value) method. From here you can either start the test using start() (goes to state 3) or you can add multiple test points using addTestPoint(server) or addTestPoints(serverList) (goes to state 1). Additionally, this is the perfect moment to set up callbacks for the onupdate(data) and onend(aborted) events.
   - 1: here you can add test points. You only need to do this if you want to use multiple test points.
        A server is defined as an object like this:
        {
            name: "User friendly name",
            server:"http://yourBackend.com/",     <---- URL to your server. You can specify http:// or https://. If your server supports both, just write // without the protocol
            dlURL:"garbage.php"    <----- path to garbage.php or its replacement on the server
            ulURL:"empty.php"    <----- path to empty.php or its replacement on the server
            pingURL:"empty.php"    <----- path to empty.php or its replacement on the server. This is used to ping the server by this selector
            getIpURL:"getIP.php"    <----- path to getIP.php or its replacement on the server
        }
        While in state 1, you can only add test points, you cannot change the test settings. When you're done, use selectServer(callback) to select the test point with the lowest ping. This is asynchronous, when it's done, it will call your callback function and move to state 2. Calling setSelectedServer(server) will manually select a server and move to state 2.
    - 2: test point selected, ready to start the test. Use start() to begin, this will move to state 3
    - 3: test running. Here, your onupdate event calback will be called periodically, with data coming from the worker about speed and progress. A data object will be passed to your onupdate function, with the following items:
            - dlStatus: download speed in mbps
            - ulStatus: upload speed in mbps
            - pingStatus: ping in ms
            - jitterStatus: jitter in ms
            - dlProgress: progress of the download test as a float 0-1
            - ulProgress: progress of the upload test as a float 0-1
            - pingProgress: progress of the ping/jitter test as a float 0-1
            - testState: state of the test (-1=not started, 0=starting, 1=download test, 2=ping+jitter test, 3=upload test, 4=finished, 5=aborted)
            - clientIp: IP address of the client performing the test (and optionally ISP and distance) 
        At the end of the test, the onend function will be called, with a boolean specifying whether the test was aborted or if it ended normally.
        The test can be aborted at any time with abort().
        At the end of the test, it will move to state 4
    - 4: test finished. You can run it again by calling start() if you want.
    Using start():
    Example call order: loadServerList, getIp, selectServer, start, onupdate, onend
    Example call order: loadServerList, getIp, addTestPoints, addTestPoint, selectServer, start, onupdate, onend
    Example call order: loadServerList, getIp, addTestPoint, selectServer, start, onupdate, onend

    Using download():
    Example call order: loadServerList, getIp, selectServer, download, onupdate, onend
    Example call order: loadServerList, getIp, addTestPoints, addTestPoint, selectServer, download, onupdate, onend
    Example call order: loadServerList, getIp, addTestPoint, selectServer, download, onupdate, onend

    Using upload():
    Example call order: loadServerList, getIp, selectServer, upload, onupdate, onend
    Example call order: loadServerList, getIp, addTestPoints, addTestPoint, selectServer, upload, onupdate, onend
    Example call order: loadServerList, getIp, addTestPoint, selectServer, upload, onupdate, onend

    Using abort():
    Example call order: loadServerList, getIp, selectServer, start, abort, onend
    Example call order: loadServerList, getIp, addTestPoints, addTestPoint, selectServer, start, abort, onend
    Example call order: loadServerList, getIp, addTestPoint, selectServer, start, abort, onend

    Using ping():
    Example call order: loadServerList, getIp, selectServer, ping, onupdate, onend
    Example call order: loadServerList, getIp, addTestPoints, addTestPoint, selectServer, ping, onupdate, onend
    Example call order: loadServerList, getIp, addTestPoint, selectServer, ping, onupdate, onend
 */

function Speedtest(type = "") {
  this._serverList = []; //when using multiple points of test, this is a list of test points
  this._selectedServer = null; //when using multiple points of test, this is the selected server
  this._settings = {}; //settings for the speedtest worker
  this._state = 0; //0=adding settings, 1=adding servers, 2=server selection done, 3=test running, 4=done
  if(type !== ""){
    this.worker = new Worker("speedtest_worker.js?r=" + type);//+ Math.random());
  }else{
    this.worker = new Worker("speedtest_worker.js?r=");//+ Math.random());
  }
}

const TestType = {
  DOWNLOAD: 'download',
  UPLOAD: 'upload',
  IP: 'ip',
  PING: 'ping',
  ALL: 'all'
};

Speedtest.prototype = {
  constructor: Speedtest,
  /**
   * @returns {number}
   * Returns the state of the test: 0=adding settings, 1=adding servers, 2=server selection done, 3=test running, 4=done
   */
  getState: function() {
    return this._state;
  },
  /**
   * @returns {void}
   * Change one of the test settings from their defaults.
   * - parameter: string with the name of the parameter that you want to set
   * - value: new value for the parameter
   * 
   * Invalid values or nonexistant parameters will be ignored by the speedtest worker.
   */
  setParameter: function(parameter, value) {
    if (this._state == 3)
      throw "You cannot change the test settings while running the test";
    this._settings[parameter] = value;
    if(parameter === "telemetry_extra"){
        this._originalExtra=this._settings.telemetry_extra;
    }
  },
  /**
   * @returns {void}
   * @throws {Error}
   * Used internally to check if a server object contains all the required elements.
   * Also fixes the server URL if needed.
   */
  _checkServerDefinition: function(server) {
    try {
      if (typeof server.name !== "string")
        throw "Name string missing from server definition (name)";
      if (typeof server.server !== "string")
        throw "Server address string missing from server definition (server)";
      if (server.server.charAt(server.server.length - 1) != "/")
        server.server += "/";
      if (server.server.indexOf("//") == 0)
        server.server = location.protocol + server.server;
      if (typeof server.dlURL !== "string")
        throw "Download URL string missing from server definition (dlURL)";
      if (typeof server.ulURL !== "string")
        throw "Upload URL string missing from server definition (ulURL)";
      if (typeof server.pingURL !== "string")
        throw "Ping URL string missing from server definition (pingURL)";
      if (typeof server.getIpURL !== "string")
        throw "GetIP URL string missing from server definition (getIpURL)";
    } catch (e) {
      throw "Invalid server definition";
    }
  },

  getTestPoints: function() {
    return this._serverList;
  },

  getSelectedServer: function() {
    return this._selectedServer;
  },

  /**
   * @returns {void}
   * @throws {Error}
   * Add a test point (multiple points of test)
   * server: the server to be added as an object. Must contain the following elements:
   *  {
   *       name: "User friendly name",
   *       server:"http://yourBackend.com/",   URL to your server. You can specify http:// or https://. If your server supports both, just write // without the protocol
   *       dlURL:"garbage.php"   path to garbage.php or its replacement on the server
   *       ulURL:"empty.php"   path to empty.php or its replacement on the server
   *       pingURL:"empty.php"   path to empty.php or its replacement on the server. This is used to ping the server by this selector
   *       getIpURL:"getIP.php"   path to getIP.php or its replacement on the server
   *   }
   */
  addTestPoint: function(server) {
    this._checkServerDefinition(server);
    if (this._state == 0) this._state = 1;
    if (this._state != 1) throw "You can't add a server after server selection";
    this._settings.mpot = true;
    this._serverList.push(server);
  },

  /**
   * @returns {void}
   * @throws {Error}
   * Same as addTestPoint, but you can pass an array of servers
   */
  addTestPoints: function(list) {
    for (var i = 0; i < list.length; i++) this.addTestPoint(list[i]);
  },

  /**
   * @returns {void}
   * @throws {Error}
   * Load a JSON server list from URL (multiple points of test)
   * 
   * url: the url where the server list can be fetched. Must be an array with objects containing the following elements:
   *  {
   *       "name": "User friendly name",
   *       "server":"http://yourBackend.com/",   URL to your server. You can specify http:// or https://. If your server supports both, just write // without the protocol
   *       "dlURL":"garbage.php"   path to garbage.php or its replacement on the server
   *       "ulURL":"empty.php"   path to empty.php or its replacement on the server
   *       "pingURL":"empty.php"   path to empty.php or its replacement on the server. This is used to ping the server by this selector
   *       "getIpURL":"getIP.php"   path to getIP.php or its replacement on the server
   *   }
   * result: callback to be called when the list is loaded correctly. An array with the loaded servers will be passed to this function, or null if it failed
   */
  loadServerList: function(url,result) {
    if (this._state == 0) this._state = 1;
    if (this._state != 1) throw "You can't add a server after server selection";
    this._settings.mpot = true;
    var xhr = new XMLHttpRequest();
    xhr.onload = function(){
      try{
        var servers=JSON.parse(xhr.responseText);
        for(var i=0;i<servers.length;i++){
          this._checkServerDefinition(servers[i]);
        }
        this.addTestPoints(servers);
        result(servers);
      }catch(e){
        result(null);
      }
    }.bind(this);
    xhr.onerror = function(){result(null);}
    xhr.open("GET",url);
    xhr.send();
  },

  /**
   * @returns {object}
   * @throws {Error}
   * Returns the selected server (multiple points of test)
   *  {
   *       "name": "User friendly name",
   *       "server":"http://yourBackend.com/",   URL to your server. You can specify http:// or https://. If your server supports both, just write // without the protocol
   *       "dlURL":"garbage.php"   path to garbage.php or its replacement on the server
   *       "ulURL":"empty.php"   path to empty.php or its replacement on the server
   *       "pingURL":"empty.php"   path to empty.php or its replacement on the server. This is used to ping the server by this selector
   *       "getIpURL":"getIP.php"   path to getIP.php or its replacement on the server
   *   }
   */
  getSelectedServer: function() {
    if (this._state < 2 || this._selectedServer == null)
      throw "No server is selected";
    return this._selectedServer;
  },

  /**
   * @returns {void}
   * @throws {Error}
   * Manually selects one of the test points (multiple points of test)
   */
  setSelectedServer: function(server) {
    this._checkServerDefinition(server);
    if (this._state == 3)
      throw "You can't select a server while the test is running";
    this._selectedServer = server;
    this._state = 2;
  },

  /**
   * @returns {void}
   * @throws {Error}
   * Automatically selects a server from the list of added test points. The server with the lowest ping will be chosen. (multiple points of test)
   * The process is asynchronous and the passed result callback function will be called when it's done, then the test can be started.
   */
  selectServer: function(result) {
    if (this._state != 1) {
      if (this._state == 0) throw "No test points added";
      if (this._state == 2) throw "Server already selected";
      if (this._state >= 3)
        throw "You can't select a server while the test is running";
    }
    if (this._selectServerCalled) throw "selectServer already called"; else this._selectServerCalled=true;
    /*this function goes through a list of servers. For each server, the ping is measured, then the server with the function selected is called with the best server, or null if all the servers were down.
     */
    var select = function(serverList, selected) {
      //pings the specified URL, then calls the function result. Result will receive a parameter which is either the time it took to ping the URL, or -1 if something went wrong.
      var PING_TIMEOUT = 2000;
      var USE_PING_TIMEOUT = true; //will be disabled on unsupported browsers
      if (/MSIE.(\d+\.\d+)/i.test(navigator.userAgent)) {
        //IE11 doesn't support XHR timeout
        USE_PING_TIMEOUT = false;
      }
      var ping = function(url, rtt) {
        url += (url.match(/\?/) ? "&" : "?") + "cors=true";
        var xhr = new XMLHttpRequest();
        var t = new Date().getTime();
        xhr.onload = function() {
          if (xhr.responseText.length == 0) {
            //we expect an empty response
            var instspd = new Date().getTime() - t; //rough timing estimate
            try {
              //try to get more accurate timing using performance API
              var p = performance.getEntriesByName(url);
              p = p[p.length - 1];
              var d = p.responseStart - p.requestStart;
              if (d <= 0) d = p.duration;
              if (d > 0 && d < instspd) instspd = d;
            } catch (e) {}
            rtt(instspd);
          } else rtt(-1);
        }.bind(this);
        xhr.onerror = function() {
          rtt(-1);
        }.bind(this);
        xhr.open("GET", url);
        if (USE_PING_TIMEOUT) {
          try {
            xhr.timeout = PING_TIMEOUT;
            xhr.ontimeout = xhr.onerror;
          } catch (e) {}
        }
        xhr.send();
      }.bind(this);

      //this function repeatedly pings a server to get a good estimate of the ping. When it's done, it calls the done function without parameters. At the end of the execution, the server will have a new parameter called pingTime, which is either the best ping we got from the server or -1 if something went wrong.
      var PINGS = 3, //up to 3 pings are performed, unless the server is down...
        SLOW_THRESHOLD = 500; //...or one of the pings is above this threshold
      var checkServer = function(server, done) {
        var i = 0;
        server.pingTime = -1;
        if (server.server.indexOf(location.protocol) == -1) done();
        else {
          var nextPing = function() {
            if (i++ == PINGS) {
              done();
              return;
            }
            ping(
              server.server + server.pingURL,
              function(t) {
                if (t >= 0) {
                  if (t < server.pingTime || server.pingTime == -1) server.pingTime = t;
                  if (t < SLOW_THRESHOLD) nextPing();
                  else done();
                } else done();
              }.bind(this)
            );
          }.bind(this);
          nextPing();
        }
      }.bind(this);
      //check servers in list, one by one
      var i = 0;
      var done = function() {
        var bestServer = null;
        for (var i = 0; i < serverList.length; i++) {
          if (
            serverList[i].pingTime != -1 &&
            (bestServer == null || serverList[i].pingTime < bestServer.pingTime)
          )
            bestServer = serverList[i];
        }
        selected(bestServer);
      }.bind(this);
      var nextServer = function() {
        if (i == serverList.length) {
          done();
          return;
        }
        checkServer(serverList[i++], nextServer);
      }.bind(this);
      nextServer();
    }.bind(this);

    //parallel server selection
    var CONCURRENCY = 6;
    var serverLists = [];
    for (var i = 0; i < CONCURRENCY; i++) {
      serverLists[i] = [];
    }
    for (var i = 0; i < this._serverList.length; i++) {
      serverLists[i % CONCURRENCY].push(this._serverList[i]);
    }
    var completed = 0;
    var bestServer = null;
    for (var i = 0; i < CONCURRENCY; i++) {
      select(
        serverLists[i],
        function(server) {
          if (server != null) {
            if (bestServer == null || server.pingTime < bestServer.pingTime)
              bestServer = server;
          }
          completed++;
          if (completed == CONCURRENCY) {
            this._selectedServer = bestServer;
            this._state = 2;
            if (result) result(bestServer);
          }
        }.bind(this)
      );
    }
  },
  /**
   * @returns {boolean}
   * Checks if the test can start by making sure the Speedtest object is in the correct state
   */
  canTheTestStart: function() {
    if (this._state == 2) {
      return true;
    }
    return false;
  },
  /**
   * @returns {void}
   * @throws {Error}
   * Validates the test readiness. Throws an error if the test is not ready to start.
   */
  validateTheTestReadiness: function(){
    if (!this.canTheTestStart()) {
      switch (this._state) {
        case 0: throw "No test points added";
        case 1: throw "You can't add a server after server selection";
        case 2: throw "Server already selected";
        case 3: throw "Test already running";
      }
    }
  },

  /**
   * @returns {boolean}
   * loop through the test_order setting and check if all the tests are defined
   * The start command requires all four tests to be defined or its state machine will break
   * The start command relies on recursion and will only break its recursion if the tests are defined and the ran test count reaches 4
   */
  areEnoughTestsDefinedToUseTheStartCommand: function () {
    
    var foundTests = 0;
    for (var i = 0; i < this._settings.test_order.length; i++) {
      if (this._settings.test_order[i] === "D" || this._settings.test_order[i] === "U" || this._settings.test_order[i] === "P" || this._settings.test_order[i] === "I") {
        foundTests++;
      }
    }
    if (foundTests === 4) {
      return true;
    }
    return false;
  },

  /**
   * @returns {void}
   * Prepares the settings based on the client
   */
  prepareTheSettingsBasedOnTheSelectedServer: function() {
    this._settings.url_dl =
      this._selectedServer.server + this._selectedServer.dlURL;
    this._settings.url_ul =
      this._selectedServer.server + this._selectedServer.ulURL;
    this._settings.url_ping =
      this._selectedServer.server + this._selectedServer.pingURL;
    this._settings.url_getIp =
      this._selectedServer.server + this._selectedServer.getIpURL;
    if (typeof this._originalExtra !== "undefined") {
      this._settings.telemetry_extra = JSON.stringify({
        server: this._selectedServer.name,
        extra: this._originalExtra
      });
    } else
      this._settings.telemetry_extra = JSON.stringify({
        server: this._selectedServer.name
      });
  },

  // store a test name
  _testName: null,
  
  getTestName: function() {
    return this._testName;
  },

  startDownloadTest: function() {
    this._testName = "download";
    this.startRequestedTest(TestType.DOWNLOAD);
  },
  startUploadTest: function() {
    this._testName = "upload";
    this.startRequestedTest(TestType.UPLOAD);
  },
  startPingTest: function() {
    this._testName = "ping";
    this.startRequestedTest(TestType.PING);
  },

  /**
   * @returns {void}
   * @throws {Error}
   * Starts the test.
   * During the test, the onupdate(data) callback function will be called periodically with data from the worker.
   * At the end of the test, the onend(aborted) function will be called with a boolean telling you if the test was aborted or if it ended normally.
   * This will run the tests in the background and will not block the main thread.
   * The tests will be ran in order as defined in the test_order setting.
   * Default test order is "IP_D_U", D=Download, U=Upload, P=Ping+Jitter, I=IP, _=1 second delay
   * This function 
   */
  start: function () {
    if (!this.areEnoughTestsDefinedToUseTheStartCommand()) {
      throw new Error("Not enough tests defined to use the start command");
    }
    this.startRequestedTest(TestType.ALL);
  },

  startRequestedTest: function (testType) {
    if (!Object.values(TestType).includes(testType)) {
      throw new Error("Invalid test type: " + testType);
    }
    try {
      this.validateTheTestReadiness();
    } catch (error) {
      throw new Error("Speedtest start event threw exception: " + error);
    }
    //this.worker = new Worker("speedtest_worker.js?r=");// + Math.random());
    this.worker.onmessage = function(e) {
      var params = e.data.split(" ",2);
      var command = params[0];
      var dataJSON = e.data.substring(command.length) || "";

      if(command === "currentStatus"){
        console.log(this._testName + " currentStatus command received");
      }


      if (command === "status") return; // do nothing
      if (command === "getSettings") return; // do nothing
      if (command === "setSettings") return; // do nothing
      if (command === "start") return; // do nothing
      if (command === "settingsUpdated") return; // do nothing
      if (command === "getIp") return; // do nothing
      if (command === "upload") return; // do nothing
      if (command === "download") return; // do nothing
      if (command === "ping") return; // do nothing
      if (command === "downloadTestFinished") return; // do nothing
      if (command === "uploadTestFinished") return; // do nothing
      if (command === "pingTestFinished") return; // do nothing
      if (command === "allTestsFinished") return; // do nothing
      if (command === "abort") return; // do nothing
      if (dataJSON === "") return; //empty message or command
      if (e.data === this._prevData) return;
      else this._prevData = e.data;
      try {
        var data = JSON.parse(dataJSON);
      } catch (error) {
        throw new Error("Failed to parse data: " + error);
      }

      if (command === "finalAllTestsResults" || command === "finalDownloadTestResults" || command === "finalUploadTestResults" || command === "finalPingTestResults") {
        clearInterval(this.updater);
        this._state = 4;
        switch (command) {
          case "finalAllTestsResults":
            if (this.onend) this.onend(false, data.testType, data.dlStatus, data.ulStatus, data.pingStatus, data.jitterStatus);
            break;
          case "finalDownloadTestResults":
            if (this.onend) this.onend(false, data.testType, data.dlStatus);
            break;
          case "finalUploadTestResults":
            if (this.onend) this.onend(false, data.testType, data.ulStatus);
            break;
          case "finalPingTestResults":
            if (this.onend) this.onend(false, data.testType, data.pingStatus, data.jitterStatus);
            break;
        }  
        /*
        try {
          if (this.onend) this.onend(data.testState == 5, data.testType, data.finalSpeed);
        } catch (e) {
          throw new Error("Speedtest onend event threw exception: " + e);
        }
        */
      }
      // update the UI
      try {
        if (this.onupdate) this.onupdate(data);
      } catch (e) {
        throw new Error("Speedtest onupdate event threw exception: " + e);
      }
      
    }.bind(this);
    this.updater = setInterval(
      function() {
        this.worker.postMessage("status");
      }.bind(this),
      200
    );

    this.prepareTheSettingsBasedOnTheSelectedServer();
    
    this._state = 3;
    switch (testType) {
      case TestType.DOWNLOAD:
        this.worker.postMessage("download " + JSON.stringify(this._settings));
        break;
      case TestType.UPLOAD:
        this.worker.postMessage("upload " + JSON.stringify(this._settings));
        break;
      case TestType.PING:
        this.worker.postMessage("ping " + JSON.stringify(this._settings));
        break;
      case TestType.IP:
        // IP test is started by the getIp function
        break;
      default:
        this.worker.postMessage("start " + JSON.stringify(this._settings) + " " + testType);
        break;
    }
  },

  /**
   * @returns {void}
   * @throws {Error}
   * Aborts the test while it's running.
   */
  abort: function() {
    if (this._state < 3) throw "You cannot abort a test that's not started yet";
    if (this._state < 4) this.worker.postMessage("abort");
  },

  /**
   * @returns {void}
   * @throws {Error}
   * Gets the IP address of the client
   */
  getIp: function(done) { 
    // Send a message to the worker to get the IP
    this.worker.postMessage("setSettings " + JSON.stringify(this._settings));
    var workerReference = this.worker;
    this.worker.onmessage = function(e) {
      
      
      // split only on first space
      var params = e.data.split(" ",2);
      var command = params[0];
      var data = e.data.substring(command.length) || "";


      switch (command) {
        case "settingsUpdated":
          workerReference.postMessage("getSettings");
          break;
        case "currentSettings":
            // Process settings
            try {
              currentSettings = JSON.parse(data);
              workerReference.postMessage("getIp");
            } catch (error) {
                console.error("Failed to parse settings:", error);
            }
            break;
        case "ipTestResults":
          if (params[1] === this._prevData) return;
          else this._prevData = params[1];
            var data = JSON.parse(e.data.substring(13));
            console.log(data);
            done(e.data.substring(13));
            break;
        // Add more cases as needed
        default:
            console.warn("Unknown command:", command);
      }
    };
  },

  /**
   * @returns {void}
   * Resets the Speedtest object and the associated web worker.
   */
  reset: function(softReset = true) {
    // Reset internal state
    
    if (!softReset) {
      this._state = 0;
      this._selectedServer = null;
      this._serverList = [];
      this._settings = {};
      this._selectServerCalled = false;
      //this.worker = new Worker("speedtest_worker.js?r=" + Math.random());
    } else if (this._state > 2) {
      this._state = 2; // Reset to server selected
    }
    this._prevData = null;
    
    

    // Reset the worker
    this.worker.postMessage("resetWorker");

    // Clear any intervals or timeouts
    if (this.updater) {
      clearInterval(this.updater);
      this.updater = null;
    }

    // Optionally, reinitialize the worker if needed
    //this.worker = new Worker("speedtest_worker.js?r=" + Math.random());
  },
};
