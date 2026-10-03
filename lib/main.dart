import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

Uint8List makeTone(List<double> freqs) {
  const rate = 44100;
  final samples = <int>[];
  for (final f in freqs) {
    final n = (rate * 0.12).toInt();
    for (var i = 0; i < n; i++) {
      final fade = min(1.0, min(i, n - i) / 400);
      samples.add((sin(2 * pi * f * i / rate) * 12000 * fade).toInt());
    }
  }
  final d = ByteData(44 + samples.length * 2);
  void s(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      d.setUint8(o + i, t.codeUnitAt(i));
    }
  }
  const e = Endian.little;
  s(0, 'RIFF');
  d.setUint32(4, 36 + samples.length * 2, e);
  s(8, 'WAVE');
  s(12, 'fmt ');
  d.setUint32(16, 16, e);
  d.setUint16(20, 1, e);
  d.setUint16(22, 1, e);
  d.setUint32(24, rate, e);
  d.setUint32(28, rate * 2, e);
  d.setUint16(32, 2, e);
  d.setUint16(34, 16, e);
  s(36, 'data');
  d.setUint32(40, samples.length * 2, e);
  for (var i = 0; i < samples.length; i++) {
    d.setInt16(44 + i * 2, samples[i], e);
  }
  return d.buffer.asUint8List();
}

@pragma('vm:entry-point')
void startCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(VpnHandler());
}

class VpnHandler extends TaskHandler {
  final player = AudioPlayer();
  final onSound = makeTone([600, 900]);
  final offSound = makeTone([900, 600]);
  bool? vpn;
  StreamSubscription? sub;

  void update(List<ConnectivityResult> list) {
    final now = list.contains(ConnectivityResult.vpn);
    if (vpn != null && now != vpn) {
      FlutterForegroundTask.updateService(
        notificationText: now ? 'VPN включён' : 'VPN выключен',
      );
      play(now ? onSound : offSound);
    }
    vpn = now;
  }

  Future<void> play(Uint8List data) async {
    try {
      await player.play(BytesSource(data));
    } catch (e) {
      FlutterForegroundTask.updateService(
        notificationText: 'Ошибка звука: $e',
      );
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    sub = Connectivity().onConnectivityChanged.listen(update);
    update(await Connectivity().checkConnectivity());
    try {
      await player.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
    } catch (e) {
      FlutterForegroundTask.updateService(
        notificationText: 'Ошибка настройки: $e',
      );
    }
    await play(onSound);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    sub?.cancel();
    player.dispose();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'vpn_sound',
      channelName: 'VPN Sound',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Home());
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool? vpn;
  StreamSubscription? sub;

  void update(List<ConnectivityResult> list) {
    setState(() => vpn = list.contains(ConnectivityResult.vpn));
  }

  Future<void> startService() async {
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'VPN Sound',
      notificationText: 'Слежу за VPN',
      callback: startCallback,
    );
  }

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(update);
    sub = Connectivity().onConnectivityChanged.listen(update);
    startService();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          vpn == null ? '...' : (vpn! ? 'VPN включён' : 'VPN выключен'),
          style: const TextStyle(fontSize: 28),
        ),
      ),
    );
  }
}
