import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ============== Config ==============
const String YUEWU_BASE = "http://103.236.99.177:24512";
const String XZS_BASE = "http://103.236.99.177:24513";
const Color kPink = Color(0xFFFFB6C1);
const Color kPinkLight = Color(0xFFFFC0CB);
const Color kPinkBg = Color(0xFFFFF0F5);

// ============== API Service ==============
class Api {
  Api._internal();
  static final Api _i = Api._internal();
  factory Api() => _i;

  String? token;
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    token = _prefs!.getString("auth_token");
  }

  Future<void> setToken(String? t) async {
    token = t;
    if (t == null) {
      await _prefs?.remove("auth_token");
    } else {
      await _prefs?.setString("auth_token", t);
    }
  }

  Map<String, String> get _h => {
        "Content-Type": "application/json",
        if (token != null) "Authorization": "Bearer $token",
      };

  Future<Map<String, dynamic>> login(String u, String p) async {
    final r = await http.post(
      Uri.parse("$YUEWU_BASE/api/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": u, "password": p}),
    );
    final d = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(d["detail"] ?? d["message"] ?? "登录失败");
    if (d["token"] != null) await setToken(d["token"]);
    return d;
  }

  Future<dynamic> _send(String method, String path, [Map<String, dynamic>? data]) async {
    final uri = Uri.parse("$XZS_BASE$path");
    final body = data == null ? null : jsonEncode(data);
    http.Response r;
    if (method == "POST") {
      r = await http.post(uri, headers: _h, body: body);
    } else {
      r = await http.get(uri, headers: _h);
    }
    if (r.statusCode == 401) {
      await setToken(null);
      throw Exception("登录已过期");
    }
    if (r.statusCode >= 400) {
      try {
        final d = jsonDecode(r.body);
        throw Exception(d["detail"] ?? "请求失败 ${r.statusCode}");
      } catch (_) {
        throw Exception("请求失败 ${r.statusCode}");
      }
    }
    if (r.body.isEmpty) return {};
    return jsonDecode(r.body);
  }

  Future<dynamic> chat(String mode, String msg, List<Map<String, String>> history, String? sid) =>
      _send("POST", "/api/chat", {
        "mode": mode,
        "message": msg,
        "history": history,
        if (sid != null) "sandboxId": sid,
      });

  Future<Map<String, dynamic>> createSandbox() async =>
      await _send("POST", "/api/sandbox/create", {});

  Future<List<dynamic>> listSandbox(String sid) async {
    final d = await _send("GET", "/api/sandbox/$sid/list");
    return d["files"] ?? [];
  }

  Future<String> zipSandbox(String sid) async {
    final uri = Uri.parse("$XZS_BASE/api/sandbox/$sid/zip");
    final r = await http.post(uri, headers: _h);
    if (r.statusCode == 200) {
      return "$XZS_BASE/api/sandbox/$sid/zip";
    }
    throw Exception("打包失败");
  }

  Future<void> destroySandbox(String sid) async {
    try {
      await _send("POST", "/api/sandbox/$sid/destroy", {});
    } catch (_) {}
  }

  Future<dynamic> saveHistory(List<dynamic> msgs) =>
      _send("POST", "/api/history", {"messages": msgs});

  Future<List<dynamic>> loadHistory() async {
    final d = await _send("GET", "/api/history");
    return d["messages"] ?? [];
  }
}

// ============== Models ==============
class ChatMsg {
  String role; // user / assistant
  String content;
  String thinking;
  String mode;
  List<dynamic>? steps;
  String? sandboxId;
  List<dynamic>? files;
  DateTime time;

  ChatMsg({
    required this.role,
    required this.content,
    this.thinking = "",
    this.mode = "fast",
    this.steps,
    this.sandboxId,
    this.files,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        "role": role,
        "content": content,
        "thinking": thinking,
        "mode": mode,
        "steps": steps,
        "sandboxId": sandboxId,
        "files": files,
        "time": time.toIso8601String(),
      };

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
        role: j["role"],
        content: j["content"],
        thinking: j["thinking"] ?? "",
        mode: j["mode"] ?? "fast",
        steps: j["steps"],
        sandboxId: j["sandboxId"],
        files: j["files"],
        time: DateTime.tryParse(j["time"] ?? "") ?? DateTime.now(),
      );
}

// ============== Main ==============
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kPink,
      primary: kPink,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: "月悟小助手",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: kPinkBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF4A4A4A),
          elevation: 0.5,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: Api().token != null ? const ChatPage() : const LoginPage(),
      routes: {
        "/login": (_) => const LoginPage(),
        "/chat": (_) => const ChatPage(),
      },
    );
  }
}

// ============== Login Page ==============
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _err;

  Future<void> _login() async {
    if (_u.text.trim().isEmpty || _p.text.isEmpty) {
      setState(() => _err = "请输入账号和密码");
      return;
    }
    setState(() { _loading = true; _err = null; });
    try {
      await Api().login(_u.text.trim(), _p.text.text);
      if (mounted) {
        Navigator.pushReplacementNamed(context, "/chat");
      }
    } catch (e) {
      setState(() => _err = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kPinkLight, kPinkBg],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 80),
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: kPink.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.assistant, size: 44, color: kPink),
                ),
                const SizedBox(height: 24),
                const Text("月悟小助手", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF4A4A4A))),
                const SizedBox(height: 8),
                Text("登录月悟账号开始使用", style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                const SizedBox(height: 48),
                TextField(
                  controller: _u,
                  decoration: const InputDecoration(hintText: "账号", prefixIcon: Icon(Icons.person_outline, color: kPink)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _p,
                  obscureText: _obscure,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: "密码",
                    prefixIcon: const Icon(Icons.lock_outline, color: kPink),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Text(_err!, style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 13)),
                ],
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Text("登录", style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                Text("没有账号？请先在月悟APP注册", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============== Chat Page ==============
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final List<ChatMsg> _msgs = [];
  bool _sending = false;
  String _mode = "fast";
  String? _sandboxId;
  List<dynamic> _sandboxFiles = [];

  final List<Map<String, String>> _modes = [
    {"key": "fast", "label": "快速", "icon": "⚡"},
    {"key": "think", "label": "思考", "icon": "💭"},
    {"key": "expert", "label": "专家", "icon": "🎓"},
    {"key": "work", "label": "工作任务", "icon": "🔧"},
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final h = await Api().loadHistory();
      setState(() {
        _msgs
          ..clear()
          ..addAll(h.map((e) => ChatMsg.fromJson(e as Map<String, dynamic>)));
      });
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      await Api().saveHistory(_msgs.map((m) => m.toJson()).toList());
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();

    // Work mode: ensure sandbox exists
    if (_mode == "work" && _sandboxId == null) {
      try {
        final sb = await Api().createSandbox();
        _sandboxId = sb["sandboxId"];
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("沙箱创建失败: $e")));
        }
        return;
      }
    }

    setState(() {
      _sending = true;
      _msgs.add(ChatMsg(role: "user", content: text, mode: _mode, time: DateTime.now()));
    });
    _scrollToBottom();

    // Build history for API (last 10 turns, only role+content)
    final hist = _msgs
        .sublist(0, _msgs.length - 1)
        .where((m) => m.role == "user" || m.role == "assistant")
        .toList()
        .reversed
        .take(10)
        .toList()
        .reversed
        .map((m) => {"role": m.role, "content": m.content})
        .toList();

    try {
      final resp = await Api().chat(_mode, text, hist, _mode == "work" ? _sandboxId : null);
      setState(() {
        _msgs.add(ChatMsg(
          role: "assistant",
          content: resp["reply"] ?? "",
          thinking: resp["thinking"] ?? "",
          mode: _mode,
          steps: resp["steps"],
          sandboxId: resp["sandboxId"] ?? _sandboxId,
          time: DateTime.now(),
        ));
      });
      // Refresh sandbox file list
      if (_mode == "work" && _sandboxId != null) {
        try {
          _sandboxFiles = await Api().listSandbox(_sandboxId!);
        } catch (_) {}
      }
    } catch (e) {
      setState(() {
        _msgs.add(ChatMsg(role: "assistant", content: "出错了: $e", time: DateTime.now()));
      });
    } finally {
      setState(() => _sending = false);
      _saveHistory();
      _scrollToBottom();
    }
  }

  Future<void> _clearChat() async {
    if (_sandboxId != null) {
      await Api().destroySandbox(_sandboxId!);
      _sandboxId = null;
      _sandboxFiles = [];
    }
    setState(() => _msgs.clear());
    _saveHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("月悟小助手", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearChat, tooltip: "清空对话"),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Api().setToken(null);
              if (mounted) Navigator.pushReplacementNamed(context, "/login");
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildModeSelector(),
          if (_mode == "work") _buildSandboxBar(),
          Expanded(child: _buildChatList()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _modes.length,
        itemBuilder: (_, i) {
          final m = _modes[i];
          final selected = _mode == m["key"];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text("${m["icon"]} ${m["label"]}"),
              selected: selected,
              onSelected: (_) {
                setState(() => _mode = m["key"]!);
              },
              selectedColor: kPink,
              labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSandboxBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFFFFE4EC),
      child: Row(
        children: [
          const Icon(Icons.memory, size: 16, color: Color(0xFFB85C7A)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _sandboxId == null
                  ? "沙箱未创建（发送消息自动创建，128MB内存/500MB存储）"
                  : "沙箱已激活: $_sandboxId  ·  ${_sandboxFiles.length} 个文件",
              style: const TextStyle(fontSize: 12, color: Color(0xFF8B4A5E)),
            ),
          ),
          if (_sandboxId != null)
            TextButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text("打包", style: TextStyle(fontSize: 12)),
              onPressed: () async {
                final url = await Api().zipSandbox(_sandboxId!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("下载链接: $url")));
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (_msgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 64, color: kPink),
            const SizedBox(height: 16),
            Text("你好，我是月悟小助手", style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text("选择模式开始对话吧", style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _msgs.length + (_sending ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _msgs.length) {
          return _buildTyping();
        }
        return _buildBubble(_msgs[i]);
      },
    );
  }

  Widget _buildTyping() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text("思考中...", style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMsg m) {
    final isUser = m.role == "user";
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? kPink : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.thinking.isNotEmpty) _buildThinking(m.thinking),
            if (m.thinking.isNotEmpty && m.content.isNotEmpty) const SizedBox(height: 6),
            SelectableText(
              m.content,
              style: TextStyle(color: isUser ? Colors.white : const Color(0xFF333333), fontSize: 15),
            ),
            if (m.steps != null && m.steps!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildSteps(m.steps!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThinking(String text) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        title: const Row(children: [
          Icon(Icons.lightbulb_outline, size: 14, color: Color(0xFFB85C7A)),
          SizedBox(width: 4),
          Text("思考过程", style: TextStyle(fontSize: 12, color: Color(0xFFB85C7A), fontWeight: FontWeight.bold)),
        ]),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFFFF0F5), borderRadius: BorderRadius.circular(8)),
            child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF666666), height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildSteps(List<dynamic> steps) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("执行步骤", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          ...steps.asMap().entries.map((e) {
            final s = e.value as Map<String, dynamic>;
            final action = s["action"] as Map<String, dynamic>;
            final obs = s["observation"] ?? "";
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                "${e.key + 1}. ${action["action"] == "run_command" ? "\$ ${action["command"]}" : action["action"] == "write_file" ? "📝 ${action["path"]}" : "✅ 完成"}\n   → $obs",
                style: const TextStyle(fontSize: 11, color: Colors.black54, height: 1.3),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _mode == "work" ? "描述要完成的编程任务..." : "输入消息...",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: _sending ? null : _send,
              backgroundColor: kPink,
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
