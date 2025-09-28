import 'dart:math';
import 'dart:typed_data';
import 'dart:async';

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
        fontFamily: 'Inter',
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
  Timer? _resetTimer;

  final double _sampleRate = 44100;
  final int _bufferSize = 4096;
  final double _clarityThreshold = 0.9;

  String _note = '...';
  double _frequency = 0.0;
  bool _isListening = false;

  String _tuningStatus = 'Start Tuning!';
  Color _statusColor = const Color(0xFFE0D5C8);
  double _centsDiff = 0.0;

  // Standard Tuning
  final List<String> _stringNames = ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];
  final List<String> _stringDisplay = ['E', 'A', 'D', 'G', 'B', 'E'];
  int _selectedStringIndex = -1;

  @override
  void initState() {
    super.initState();
    //Request microphone permission when app starts
    _setup();
  }

  Future<void> _setup() async {
    await Permission.microphone.request();
    await _audioCapture.init();
    // Create pitch detector
    _pitchDetector = PitchDetector(
      audioSampleRate: _sampleRate,
      bufferSize: _bufferSize,
    );
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
    const Map<String, int> _noteMap = {
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
    final semitonesFromA4 = _noteMap[note]!;
    final semitones = semitonesFromA4 + (octave - 4) * 12;

    return 440.0 * pow(2, semitones / 12.0);
  }

  void _updateTuningStatus(double detectedFreq) {
    if (_selectedStringIndex == -1) return;

    final targetNote = _stringNames[_selectedStringIndex];
    final targetFreq = _noteToFreq(targetNote);
    final newCentsDiff = 1200 * (log(detectedFreq / targetFreq) / log(2));

    setState(() {
      _centsDiff = newCentsDiff;
      if (newCentsDiff.abs() < 5) {
        _tuningStatus = 'Perfect!';
        _statusColor = const Color(0xFF5ED169);
      } else if (newCentsDiff > 0) {
        _tuningStatus = 'Too sharp! Tune down';
        _statusColor = const Color(0xFF5E9EDD);
      } else {
        _tuningStatus = 'Too flat! Tune up';
        _statusColor = const Color(0xFFE09758);
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
    if (_isListening && _selectedStringIndex == index) {
      await _stopCapture();
    } else {
      setState(() {
        _selectedStringIndex = index;
        _tuningStatus = 'Listening';
        _statusColor = const Color(0xFFE0D5C8);
        _centsDiff = 0.0;
      });
    }

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
        _resetTimer?.cancel();
        if (mounted) {
          _updateTuningStatus(result.pitch);
        }
      } else {
        if (_resetTimer == null || !_resetTimer!.isActive) {
          _resetTimer = Timer(const Duration(microseconds: 800), () {
            if (mounted && _isListening) {
              setState(() {
                _tuningStatus = 'Listening';
                _statusColor = const Color(0xFFE0D5C8);
                _centsDiff = 0.0;
              });
            }
          });
        }
      }
    }
  }

  Future<void> _stopCapture() async {
    _resetTimer?.cancel();
    await _audioCapture.stop();
    setState(() {
      _isListening = false;
      _selectedStringIndex = -1;
      _tuningStatus = 'Start Tuning';
      _statusColor = const Color(0xFFE0D5C8);
      _centsDiff = 0.0;
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _stopCapture();
    super.dispose();
  }

  //----------------UI------------------

  // Widget for displaying tappable notes to tune
  Widget _buildTuningNotesButtons(int index) {
    final isSelected = _selectedStringIndex == index;
    return GestureDetector(
      onTap: () => _onStringSelected(index),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? const Color(0xFF3D352E) : const Color(0xFFE0D5C8),
        ),
        child: Text(
          _stringDisplay[index],
          style: TextStyle(
            color: isSelected
                ? const Color(0xFFE0D5C8)
                : const Color(0xFF3D352E),
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFFF5E9),
      appBar: AppBar(
        title: Text('Guitar Tuner', style: TextStyle(color: Color(0xFFFFF5E9))),
        backgroundColor: Color(0xFF3D352E),
      ),
      body: Center(
        child: Column(
          children: [
            const Spacer(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 230,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor,
              ),
              child: Center(
                child: _isListening && _selectedStringIndex != -1
                    ? Text(
                        _stringDisplay[_selectedStringIndex],
                        style: const TextStyle(
                          color: Color(0xFF3D352E),
                          fontSize: 120,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : const Icon(
                        Icons.music_note,
                        color: Color(0xFF3D352E),
                        size: 120,
                      ),
              ),
            ),

            const SizedBox(height: 30),
            SizedBox(
              height: 50,
              width: 330,
              child: CustomPaint(
                painter: LinearGaugePainter(cents: _centsDiff),
              ),
            ),

            const SizedBox(height: 30),
            Text(
              _tuningStatus,
              style: const TextStyle(color: Color(0xFF8A7F75), fontSize: 20),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  6,
                  (index) => _buildTuningNotesButtons(index),
                ),
              ),
            ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

class LinearGaugePainter extends CustomPainter {
  final double cents;
  LinearGaugePainter({required this.cents});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Color(0xFF3D352E)
      ..strokeWidth = 2;

    final center = size.width / 2;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      linePaint,
    );

    final tickPaint = Paint()..color = Color(0xFF3D352E);

    _drawTick(canvas, center, size.height, tickPaint, 15);
    _drawTick(canvas, 0, size.height, tickPaint, 10);
    _drawTick(canvas, size.width, size.height, tickPaint, 10);

    _drawText(canvas, '0', center, size.height - 15);
    _drawText(canvas, '-50', 0, size.height - 15);
    _drawText(canvas, '+50', size.width, size.height - 15);
    _drawText(canvas, '♭', -10, size.height - 10, fontSize: 32);
    _drawText(canvas, '♯', size.width + 10, size.height - 10, fontSize: 28);

    final indicatorPaint = Paint()..color = Color(0xFF3D352E);
    final clampedCents = cents.clamp(-50.0, 50.0);
    final indicatorX = center + (clampedCents / 50.0) * center;
    final lineY = size.height / 2;

    final path = Path();
    path.moveTo(indicatorX, lineY - 13.0);
    path.lineTo(indicatorX - 10, lineY - 25);
    path.lineTo(indicatorX + 10, lineY - 25);
    path.close();
    canvas.drawPath(path, indicatorPaint);
  }

  void _drawTick(
    Canvas canvas,
    double x,
    double height,
    Paint paint,
    double tickHeight,
  ) {
    final paint = Paint()..strokeWidth = 2;
    canvas.drawLine(
      Offset(x, height / 2 - tickHeight / 2),
      Offset(x, height / 2 + tickHeight / 2),
      paint,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y, {
    double fontSize = 14,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Color(0xFF3D352E), fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, y));
  }

  @override
  bool shouldRepaint(covariant LinearGaugePainter oldDelegate) {
    return oldDelegate.cents != cents;
  }
}
