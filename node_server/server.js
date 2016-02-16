// var app = require('express')();

var WebsocketServer = require('websocket').server;
var http = require('http') //.Server(app);
var conf = require('./config.json')

var server = http.createServer(function(req, res) {
  console.log((new Date()) + ' recieved request for ' + req.url);
  res.writeHead(404);
  res.end();
});

server.listen(conf.port, function() {
  console.log((new Date()) + ' Server is listening on port ' + conf.port);
});

wsServer = new WebsocketServer({
  httpServer: server,
  autoAcceptConnections: false
});

function originIsAllowed(origin) {
  return true;
}

wsServer.on('request', function(req) {
  if (!originIsAllowed(req.origin)) {
    req.reject();
    console.log('connection rejected');
  }

  var connection = req.accept('distributed_hashcracker_protocol', req.origin);
  console.log((new Date()) + 'connection accepted.');

  connection.on('message', function(message) {
    if (message.type === 'utf8') {
            console.log('Received Message: ' + message.utf8Data);
            connection.sendUTF(message.utf8Data);
        }
        else if (message.type === 'binary') {
            console.log('Received Binary Message of ' + message.binaryData.length + ' bytes');
            connection.sendBytes(message.binaryData);
        }
  });
});

function exitHandler(options, err) {
  console.log("cleaning up");
  // wsServer.close();
  server.close();
  if (options.cleanup) console.log('clean');
  if (err) console.log(err.stack);
  if (options.exit) process.exit();
}

//do something when app is closing
process.on('exit', exitHandler.bind(null,{cleanup:true}));

//catches ctrl+c event
process.on('SIGINT', exitHandler.bind(null, {exit:true}));

//catches SIGTERM event
process.on('SIGTERM', exitHandler.bind(null, {exit:true}));

//catches uncaught exceptions
process.on('uncaughtException', exitHandler.bind(null, {exit:true}));
