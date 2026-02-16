import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_static/shelf_static.dart';

import 'superlatives_server.dart';

bool envFlag(String name, {bool defaultValue = false}) {
  var raw = Platform.environment[name];
  if (raw == null) return defaultValue;

  switch (raw.trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "on":
      return true;
    case "0":
    case "false":
    case "no":
    case "off":
      return false;
    default:
      return defaultValue;
  }
}

void main(List<String> args) async {
  var superlativesEnabled = envFlag("SUPERLATIVES_ENABLED", defaultValue: true);
  var game = await SuperlativesServer.load();

  final wsHandler = webSocketHandler((s) => game.connectSocket(s));
  final staticHandler =
      createStaticHandler('./web', defaultDocument: 'index.html');
  final handler = Cascade().add(wsHandler).add(staticHandler).handler;

  // Use the LISTENIP environment variable, or fallback on the loopback
  // address.
  late InternetAddress ip;
  if (Platform.environment['LISTENIP'] != null) {
    ip = InternetAddress(Platform.environment['LISTENIP']!);
  } else {
    ip = InternetAddress.loopbackIPv4;
  }

  // Configure a pipeline that logs requests.
  final pipeline = Pipeline().addMiddleware(logRequests()).addHandler(handler);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '36912');
  final server = await serve(pipeline, ip, port);
  print('Server listening on port ${server.port}');
  print('SUPERLATIVES_ENABLED=$superlativesEnabled');

  // Shut down on SIGTERM
  ProcessSignal.sigterm.watch().listen((sig) {
    server.close();
    exit(0);
  });
}

log(String s) {
  print("${DateTime.now().toString()} $s");
}
