import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

const kDefaults = {
  'gemini': 'gemini-2.5-flash',
  'groq': 'llama-3.3-70b-versatile',
  'openrouter': 'openrouter/free',
  'openai': 'gpt-4o-mini',
  'anthropic': 'claude-3-5-haiku-20241022',
};

const kNames = {
  'gemini': 'Gemini',
  'groq': 'Groq',
  'openrouter': 'OpenRouter',
  'openai': 'OpenAI',
  'anthropic': 'Claude (Anthropic)',
};

const kOpenAiUrls = {
  'groq': 'https://api.groq.com/openai/v1/chat/completions',
  'openrouter': 'https://openrouter.ai/api/v1/chat/completions',
  'openai': 'https://api.openai.com/v1/chat/completions',
};

String detectProvider(String k) {
  if (k.startsWith('sk-ant-')) return 'anthropic';
  if (k.startsWith('sk-or-')) return 'openrouter';
  if (k.startsWith('gsk_')) return 'groq';
  if (k.startsWith('sk-')) return 'openai';
  return 'gemini';
}

const kSystem =
    '''Sen Türk bir Romence öğretmenisin. Öğrenci Romanya'ya gitmek için konsolosluk görüşmesine hazırlanıyor.
Açıklamaları Türkçe yap. Romence cümleleri kısa öğret, Romence cümleleri her zaman „ ” işaretleri içine yaz ve Türkçe okunuşunu parantez içinde yaz.
Öğrencinin mesajları konuşma tanıma ile yazıya çevriliyor, bu yüzden noktalama ve büyük küçük harf farklarını yok say.
Öğrenci bir Romence cümleyi söylemeye çalıştıysa ve yazı hedef cümleden çok farklıysa, "Şöyle duydum: ..." diye yaz, doğru cümleyi tekrar söylemesini iste. Yazı hedefe yakınsa onu tebrik et.
Hataları nazikçe düzelt. Her cevabın en fazla 5-6 cümle olsun, sonunda öğrenciye tek bir kısa görev ver.
Cevapların sesli okunacak, bu yüzden emoji, yıldız ve madde işareti kullanma.''';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Romence Hoca',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const Root(),
      );
}

// Anahtar var mı diye bakar: yoksa kurulum ekranı, varsa sohbet ekranı.
class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  String? _key;
  String _model = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _key = p.getString('api_key') ?? p.getString('gemini_key');
      _model = p.getString('model') ?? '';
      _loaded = true;
    });
  }

  Future<void> _saveKey(String k, String m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('api_key', k.trim());
    await p.setString('model', m.trim());
    if (!mounted) return;
    setState(() {
      _key = k.trim();
      _model = m.trim();
    });
  }

  Future<void> _clearKey() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('api_key');
    await p.remove('gemini_key');
    await p.remove('model');
    if (!mounted) return;
    setState(() {
      _key = null;
      _model = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_key == null || _key!.isEmpty) {
      return KeyPage(onSave: _saveKey);
    }
    return ChatPage(apiKey: _key!, model: _model, onChangeKey: _clearKey);
  }
}

class KeyPage extends StatefulWidget {
  final Future<void> Function(String, String) onSave;
  const KeyPage({super.key, required this.onSave});

  @override
  State<KeyPage> createState() => _KeyPageState();
}

class _KeyPageState extends State<KeyPage> {
  final _c = TextEditingController();
  final _m = TextEditingController();
  String _err = '';

  @override
  void dispose() {
    _c.dispose();
    _m.dispose();
    super.dispose();
  }

  void _save() {
    final k = _c.text.trim();
    if (k.length < 20 || k.contains(' ')) {
      setState(
          () => _err = 'Anahtar eksik ya da hatalı görünüyor. Tekrar kopyala.');
      return;
    }
    widget.onSave(k, _m.text);
  }

  @override
  Widget build(BuildContext context) {
    final k = _c.text.trim();
    final prov = detectProvider(k);
    return Scaffold(
      appBar: AppBar(title: const Text('Romence Hoca')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Başlamak için anahtarını gir',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sana verilen anahtarı aşağıdaki kutuya yapıştır. '
              'Anahtar sadece bu telefonda saklanır.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _c,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() => _err = ''),
              decoration: InputDecoration(
                labelText: 'Anahtar',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (k.length >= 8)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Algılanan: ${kNames[prov]}'),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _m,
              decoration: InputDecoration(
                labelText: 'Model adı (isteğe bağlı)',
                hintText: kDefaults[prov],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_err.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Kaydet', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Msg {
  final String role; // 'user' veya 'model'
  final String text;
  Msg(this.role, this.text);
}

class ChatPage extends StatefulWidget {
  final String apiKey;
  final String model;
  final Future<void> Function() onChangeKey;
  const ChatPage({
    super.key,
    required this.apiKey,
    required this.model,
    required this.onChangeKey,
  });

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

  String get _prov => detectProvider(widget.apiKey);
  String get _model =>
      widget.model.isEmpty ? kDefaults[_prov]! : widget.model;

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

  Future<void> _askChangeKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Anahtarı değiştir'),
        content: Text(
            'Kayıtlı anahtar silinecek ve yenisini gireceksin.\nŞu an: ${kNames[_prov]} / $_model'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Değiştir')),
        ],
      ),
    );
    if (ok == true) await widget.onChangeKey();
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

  String _cut(String t) => t.length > 1000 ? t.substring(0, 1000) : t;

  List<Msg> _recent() {
    var r = _msgs.length > 12
        ? _msgs.sublist(_msgs.length - 12)
        : List<Msg>.from(_msgs);
    while (r.isNotEmpty && r.first.role != 'user') {
      r = r.sublist(1);
    }
    return r;
  }

  Future<String> _askGemini() async {
    var r = '';
    for (var i = 0; i < 3; i++) {
      r = await _askOnce();
      if (!r.startsWith('API hatası 503') && !r.startsWith('API hatası 429')) {
        return r;
      }
      await Future.delayed(Duration(seconds: 2 + i * 2));
    }
    if (r.startsWith('API hatası 429')) {
      return 'Bugünlük kullanım hakkın dolmuş olabilir. Yarın tekrar dene.';
    }
    return 'Sunucu şu an yoğun, biraz sonra tekrar dene.';
  }

  Future<String> _askOnce() async {
    final recent = _recent();
    final prov = _prov;
    final Uri url;
    final Map<String, String> headers;
    final Map<String, dynamic> payload;

    if (prov == 'gemini') {
      url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent');
      headers = {
        'Content-Type': 'application/json',
        'x-goog-api-key': widget.apiKey,
      };
      payload = {
        'system_instruction': {
          'parts': [
            {'text': kSystem}
          ]
        },
        'contents': recent
            .map((m) => {
                  'role': m.role,
                  'parts': [
                    {'text': _cut(m.text)}
                  ],
                })
            .toList(),
      };
    } else if (prov == 'anthropic') {
      url = Uri.parse('https://api.anthropic.com/v1/messages');
      headers = {
        'Content-Type': 'application/json',
        'x-api-key': widget.apiKey,
        'anthropic-version': '2023-06-01',
      };
      payload = {
        'model': _model,
        'max_tokens': 700,
        'system': kSystem,
        'messages': recent
            .map((m) => {
                  'role': m.role == 'model' ? 'assistant' : 'user',
                  'content': _cut(m.text),
                })
            .toList(),
      };
    } else {
      url = Uri.parse(kOpenAiUrls[prov]!);
      headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.apiKey}',
      };
      payload = {
        'model': _model,
        'messages': [
          {'role': 'system', 'content': kSystem},
          ...recent.map((m) => {
                'role': m.role == 'model' ? 'assistant' : 'user',
                'content': _cut(m.text),
              }),
        ],
      };
    }

    final res = await http
        .post(url, headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 40));
    final body = utf8.decode(res.bodyBytes);

    if (res.statusCode != 200) {
      final low = body.toLowerCase();
      if (res.statusCode == 401 ||
          res.statusCode == 403 ||
          (res.statusCode == 400 && low.contains('api key'))) {
        return 'Anahtar geçersiz görünüyor. Sağ üstteki anahtar ikonuna basıp doğru anahtarı gir.';
      }
      final short = body.length > 300 ? body.substring(0, 300) : body;
      return 'API hatası ${res.statusCode} (${kNames[prov]}): $short';
    }

    final data = jsonDecode(body);
    String text = '';
    if (prov == 'gemini') {
      final parts = data['candidates']?[0]?['content']?['parts'] as List?;
      text = parts?.map((p) => p['text'] ?? '').join('') ?? '';
    } else if (prov == 'anthropic') {
      final list = data['content'] as List?;
      text = list
              ?.where((p) => p['type'] == 'text')
              .map((p) => p['text'] ?? '')
              .join('') ??
          '';
    } else {
      text = data['choices']?[0]?['message']?['content']?.toString() ?? '';
    }
    return text.isEmpty ? 'Cevap alamadım, tekrar dener misin?' : text;
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
      reply = await _askGemini();
    } catch (e) {
      reply = 'Hata: $e';
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
            tooltip: 'Anahtarı değiştir',
            icon: const Icon(Icons.vpn_key),
            onPressed: _askChangeKey,
          ),
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
