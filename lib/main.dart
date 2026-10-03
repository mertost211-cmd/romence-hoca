import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

const kServer = 'https://romence-hoca.mertost211.workers.dev';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Romence Hoca',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const ChatPage(),
      );
}

class Msg {
  final String role; // 'user' veya 'model'
  final String text;
  Msg(this.role, this.text);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _msgs = <Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _stt = SpeechToText();
  final _tts = FlutterTts();

  bool _sttReady = false;
  bool _listening = false;
  bool _busy = false;
  bool _auto = true;
  bool _speakOn = true;
  bool _stopFlag = false;
  String _lang = 'tr_TR';
  String _partial = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _sttReady = await _stt.initialize(
      onError: (e) {
        if (mounted) setState(() => _listening = false);
      },
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
    );
    await _tts.awaitSpeakCompletion(true);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stt.cancel();
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _listen() async {
    if (!_sttReady) {
      _snack('Mikrofon izni verilmedi ya da konuşma tanıma yok.');
      return;
    }
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    _stopFlag = true;
    await _tts.stop();
    setState(() {
      _listening = true;
      _partial = '';
    });
    await _stt.listen(
      localeId: _lang,
      listenFor: const Duration(seconds: 40),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (r) {
        setState(() => _partial = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _listening = false);
          final t = r.recognizedWords.trim();
          if (t.isNotEmpty) _send(t);
        }
      },
    );
  }

  Future<void> _send(String text) async {
    if (_busy || text.trim().isEmpty) return;
    _stopFlag = false;
    setState(() {
      _msgs.add(Msg('user', text.trim()));
      _busy = true;
      _partial = '';
    });
    _input.clear();
    _scrollDown();

    String reply;
    try {
      final res = await http
          .post(
            Uri.parse(kServer),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': _msgs
                  .map((m) => {'role': m.role, 'text': m.text})
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      reply = (data['reply'] ?? '').toString();
      if (reply.isEmpty) reply = 'Cevap alamadım, tekrar dener misin?';
    } catch (e) {
      reply = 'Bağlantı hatası. İnternetini kontrol et.';
    }

    if (!mounted) return;
    setState(() {
      _msgs.add(Msg('model', reply));
      _busy = false;
    });
    _scrollDown();

    if (_speakOn) await _speak(reply);
    if (_auto && _speakOn && mounted && !_stopFlag) _listen();
  }

  // Romence kısımlar („ ” içindekiler) Romence sesle, gerisi Türkçe sesle okunur.
  Future<void> _speak(String reply) async {
    final clean = reply
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(
            RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true),
            ' ')
        .replaceAll(RegExp(r'[*#_`>]'), ' ');

    final re = RegExp(r'[„“"]([^”“"]+)[”“"]');
    final parts = <MapEntry<String, String>>[];
    var last = 0;
    for (final m in re.allMatches(clean)) {
      if (m.start > last) {
        parts.add(MapEntry('tr-TR', clean.substring(last, m.start)));
      }
      parts.add(MapEntry('ro-RO', m.group(1)!));
      last = m.end;
    }
    if (last < clean.length) {
      parts.add(MapEntry('tr-TR', clean.substring(last)));
    }

    for (final p in parts) {
      if (_stopFlag) break;
      final t = p.value.trim();
      if (t.length < 2) continue;
      await _tts.setLanguage(p.key);
      await _tts.speak(t);
    }
  }

  Future<void> _stopSpeaking() async {
    _stopFlag = true;
    await _tts.stop();
  }

  Widget _bubble(Msg m) {
    final cs = Theme.of(context).colorScheme;
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: isUser ? cs.primaryContainer : cs.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(m.text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Romence Hoca'),
        actions: [
          IconButton(
            tooltip: 'Sesi aç/kapat',
            icon: Icon(_speakOn ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() => _speakOn = !_speakOn);
              if (!_speakOn) _stopSpeaking();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'tr_TR', label: Text('Türkçe')),
                      ButtonSegment(value: 'ro_RO', label: Text('Română')),
                    ],
                    selected: {_lang},
                    onSelectionChanged: (s) => setState(() => _lang = s.first),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Otomatik dinle'),
                      Switch(
                        value: _auto,
                        onChanged: (v) => setState(() => _auto = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _msgs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Merhaba! Ben Romence öğretmenin.\n\n'
                          'Mikrofon butonuna bas ve "Merhaba, derse başlayalım" de '
                          'ya da aşağıya yaz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) => _bubble(_msgs[i]),
                    ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Öğretmen yazıyor...'),
              ),
            if (_listening)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _partial.isEmpty ? 'Dinliyorum...' : _partial,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: 'Yaz...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _send(_input.text),
                  ),
                  FloatingActionButton(
                    onPressed: _listen,
                    backgroundColor: _listening
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    child: Icon(_listening ? Icons.stop : Icons.mic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
