import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

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
  final player = AudioPlayer();
  final onSound = makeTone([600, 900]);
  final offSound = makeTone([900, 600]);
  bool? vpn;
  StreamSubscription? sub;

  void update(List<ConnectivityResult> list) {
    final now = list.contains(ConnectivityResult.vpn);
    if (vpn != null && now != vpn) {
      player.play(BytesSource(now ? onSound : offSound));
    }
    setState(() => vpn = now);
  }

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(update);
    sub = Connectivity().onConnectivityChanged.listen(update);
  }

  @override
  void dispose() {
    sub?.cancel();
    player.dispose();
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
