import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guitar Tuner',
      theme: ThemeData(
        primarySwatch: Colors.brown,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: TunerHomePage(),
    );
  }
}

class TunerHomePage extends StatefulWidget {
  const TunerHomePage({super.key});

  @override
  State<TunerHomePage> createState() => _TunerHomePageState();
}

class _TunerHomePageState extends State<TunerHomePage> {
  final _audioCapture = FlutterAudioCapture();
  PitchDetector? _pitchDetector;

  final double _sampleRate = 44100;
  final int _bufferSize = 4096;
  final double _clarityThreshold = 0.9;

  String _note = '...';
  double _frequency = 0.0;
  bool _isListening = false;

  String _tuningStatus = 'Start Tuning!';
  Color _statusColor = const Color(0x3D352E);
  int _selectedStringIndex = -1;

  // Standard Tuning
  final List<String> _stringNames = ['E3', 'A3', 'D3', 'G3', 'B4', 'E4'];
  final List<String> stringDisplay = ['E', 'A', 'D', 'G', 'B', 'E'];

  @override
  void initState() {
    super.initState();
    //Request microphone permission when app starts
    _setup();
  }

  Future<void> _setup() async {
    await _requestPermission();
    await _audioCapture.init();
    // Create pitch detector
    _pitchDetector = PitchDetector(
      audioSampleRate: _sampleRate,
      bufferSize: _bufferSize,
    );
  }

  Future<void> _requestPermission() async {
    final status = await Permission.microphone.request();
    // Handles permission rejected case
    if (status != PermissionStatus.granted) {
      setState(() {
        _note = 'Microphone request denied';
      });
    }
  }

  String _freqToNote(double frequency) {
    if (frequency <= 0) return '...';
    List<String> noteCycle = [
      'A',
      'A#',
      'B',
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
    ];

    int semitonesFromA4 = (12 * log(frequency / 440) / log(2)).round();

    int index = ((semitonesFromA4 % 12) + 12) % 12;
    int octave = 4 + (semitonesFromA4 ~/ 12); // Integer division

    return ('${noteCycle[index]}$octave');
  }

  double _noteToFreq(String noteName) {
    // Map representing no. of semitones from A
    const Map<String, int> noteMap = {
      'A': 0,
      'A#': 1,
      'B': 2,
      'C': -9,
      'C#': -8,
      'D': -7,
      'D#': -6,
      'E': -5,
      'F': -4,
      'F#': -3,
      'G': -2,
      'G#': -1,
    };

    // Parse note name into note and octave
    final note = noteName.substring(0, noteName.length - 1);
    final octave = int.parse(noteName.substring(noteName.length - 1));

    // Calculate number of semitones from A
    final semitonesFromA4 = noteMap[note]!;
    final semitones = semitonesFromA4 + (octave - 4) * 12;

    return 440.0 * pow(2, semitones / 12.0);
  }

  void _updateTuningStatus(double detectedFreq) {
    if (_selectedStringIndex == -1) return;

    final targetNote = _stringNames[_selectedStringIndex];
    final targetFreq = _noteToFreq(targetNote);
    final newCentsDiff = 1200 * (log(detectedFreq / targetFreq) / log(2));

    setState(() {
      if (newCentsDiff.abs() < 5) {
        _tuningStatus = 'Perfect!';
        _statusColor = const Color(0x005ED169);
      } else if (newCentsDiff > 0) {
        _tuningStatus = 'Too sharp! Tune down';
        _statusColor = const Color(0x005E9EDD);
      } else {
        _tuningStatus = 'Too flat! Tune up';
        _statusColor = const Color(0x00E09758);
      }
    });
  }

  //Toggles audio on/off
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopCapture();
    } else {
      await _startCapture();
    }
  }

  Future<void> _onStringSelected(int index) async {
    setState(() {
      _selectedStringIndex = index;
      _tuningStatus = 'Listening';
      _statusColor = const Color(0x00E0D5C8);
      // _centsDiff = 0.0;
    });

    if (!_isListening) {
      await _startCapture();
    }
  }

  Future<void> _startCapture() async {
    // Ensure permission is granted
    if (!await Permission.microphone.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is denied')),
      );
      return;
    }

    await _audioCapture.start(
      (dynamic obj) {
        _processAudioBuffer(obj);
      },
      (err) {
        print('Error capturing audio: $err');
        setState(() {
          _isListening = false;
        });
      },
      sampleRate: _sampleRate.toInt(),
      bufferSize: _bufferSize,
    );

    setState(() {
      _isListening = true;
    });
  }

  Future<void> _processAudioBuffer(dynamic obj) async {
    // Convert audio data from dynamic list to double type list
    if (obj is List<dynamic>) {
      final buffer = (obj.map((e) => e as double).toList());
      final floatBuffer = Float32List.fromList(buffer);
      final result = await _pitchDetector?.getPitchFromFloatBuffer(floatBuffer);

      if (result != null && result.probability > _clarityThreshold) {
        if (mounted) {
          _updateTuningStatus(result.pitch);
        }
      }
    }
  }

  Future<void> _stopCapture() async {
    await _audioCapture.stop();
    setState(() {
      _isListening = false;
      _selectedStringIndex = -1;
    });
  }

  @override
  void dispose() {
    _stopCapture();
    super.dispose();
  }

  //------------UI------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown,
      appBar: AppBar(
        title: Text('Guitar Tuner Prototype'),
        backgroundColor: Colors.brown[200],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Note detected',
              style: TextStyle(color: Colors.white, fontSize: 28),
            ),
            Text(_note, style: TextStyle(color: Colors.white, fontSize: 28)),
            SizedBox(height: 10),
            Text(
              '${_frequency.toStringAsFixed(2)} Hz',
              style: TextStyle(color: Colors.grey, fontSize: 24),
            ),
            SizedBox(height: 40),
            FloatingActionButton.extended(
              onPressed: () {
                _toggleListening();
              },
              label: Text(_isListening ? 'Stop' : 'Start'),
              icon: Icon(_isListening ? Icons.stop : Icons.mic),
            ),
          ],
        ),
      ),
    );
  }
}
