import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'src/storage_io.dart'
    if (dart.library.html) 'src/storage_web.dart'
    as storage;
import 'options_screen.dart';
import 'models/ollama_models.dart';
import 'services/ollama_service.dart';
import 'utils/app_utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  static const _prefsThemeKey = 'theme_mode';

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final v = await storage.loadTheme(_prefsThemeKey) ?? 'system';
    setState(() {
      if (v == 'light')
        _themeMode = ThemeMode.light;
      else if (v == 'dark')
        _themeMode = ThemeMode.dark;
      else
        _themeMode = ThemeMode.system;
    });
  }

  Future<void> _setThemeMode(ThemeMode m) async {
    final s = m == ThemeMode.light
        ? 'light'
        : (m == ThemeMode.dark ? 'dark' : 'system');
    await storage.saveTheme(_prefsThemeKey, s);
    setState(() => _themeMode = m);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LittleOllama',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      home: ModelsPage(themeMode: _themeMode, onThemeChanged: _setThemeMode),
    );
  }
}

class ModelsPage extends StatefulWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeChanged;

  const ModelsPage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  // Default endpoint (will be loaded/saved to prefs). Use localhost base by default.
  String _endpoint = 'http://localhost:11434';
  late Future<List<Map<String, dynamic>>> _futureModels;
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  static const _prefsKeyEndpoint = 'ollama_endpoint';
  static const _prefsKeyPollingInterval = 'polling_interval';
  String? _version;
  String? _running;
  Timer? _pollingTimer;
  int _pollingInterval = 0; // 0 = manual only

  @override
  void initState() {
    super.initState();
    _loadEndpointAndFetch();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _loadEndpointAndFetch() async {
    final stored = await storage.loadEndpoint(_prefsKeyEndpoint);
    if (stored != null && stored.isNotEmpty) {
      // if stored value lacks a scheme, add http by default
      if (!stored.startsWith('http://') && !stored.startsWith('https://')) {
        _endpoint = 'http://$stored';
      } else {
        _endpoint = stored;
      }
    }

    // Load polling interval
    final pollingStr = await storage.loadTheme(_prefsKeyPollingInterval);
    if (pollingStr != null) {
      _pollingInterval = int.tryParse(pollingStr) ?? 0;
    }

    setState(() {
      _futureModels = fetchModels();
    });
    // fetch version and running info
    _fetchVersion();
    _fetchRunning();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    if (_pollingInterval > 0) {
      _pollingTimer = Timer.periodic(Duration(seconds: _pollingInterval), (timer) {
        _fetchVersion();
        _fetchRunning();
      });
    }
  }

  void _onEndpointChanged(String newEndpoint) {
    setState(() {
      _endpoint = newEndpoint;
      _futureModels = fetchModels();
    });
    _fetchVersion();
    _fetchRunning();
  }

  void _onPollingIntervalChanged(int newInterval) {
    setState(() {
      _pollingInterval = newInterval;
    });
    _startPolling();
  }

  Future<List<Map<String, dynamic>>> fetchModels() async {
    // Use the base URL and append the tags API path so users can save a base URL only.
    final base = _baseUrlFromEndpoint();
    final uri = Uri.parse('$base/api/tags');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.reasonPhrase}',
      );
    }

    final body = json.decode(response.body);

    List items = [];
    if (body is List) {
      items = body;
    } else if (body is Map<String, dynamic>) {
      // handle several common shapes
      if (body['tags'] is List) {
        items = body['tags'];
      } else if (body['models'] is List) {
        items = body['models'];
      } else if (body['installed'] is List) {
        items = body['installed'];
      } else {
        // unknown: wrap single object
        items = [body];
      }
    } else {
      throw Exception('Unexpected response format');
    }

    // Ensure each entry is a Map<String, dynamic>
    return items.map<Map<String, dynamic>>((e) {
      if (e is Map<String, dynamic>) return e;
      if (e is Map) return Map<String, dynamic>.from(e);
      return {'value': e.toString()};
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureModels = fetchModels();
    });
    await _futureModels;
    await _fetchVersion();
    await _fetchRunning();
  }

  // Build base URL (scheme + host + optional port) from the configured endpoint
  String _baseUrlFromEndpoint() {
    try {
      final uri = Uri.parse(_endpoint);
      final host = uri.host;
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
      final portPart = uri.hasPort ? ':${uri.port}' : '';
      return '$scheme://$host$portPart';
    } catch (_) {
      return _endpoint; // fallback
    }
  }

  Future<void> _fetchVersion() async {
    try {
      final base = _baseUrlFromEndpoint();
      final uri = Uri.parse('$base/api/version');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        String? ver;
        if (body is Map && body['version'] != null)
          ver = body['version'].toString();
        else if (body is String)
          ver = body;
        else if (body is Map && body['version_string'] != null)
          ver = body['version_string'].toString();
        else
          ver = body.toString();
        setState(() => _version = ver);
      } else {
        setState(() => _version = 'err:${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _version = null);
    }
  }

  Future<void> _fetchRunning() async {
    try {
      final base = _baseUrlFromEndpoint();
      final uri = Uri.parse('$base/api/ps');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        String? running;
        List items = [];
        if (body is List) {
          items = body;
        } else if (body is Map) {
          if (body['models'] is List) {
            items = body['models'];
          } else if (body['processes'] is List) {
            items = body['processes'];
          } else if (body['ps'] is List) {
            items = body['ps'];
          } else {
            items = [body];
          }
        }

        // Parse running models with detailed info
        final runningModels = <Map<String, dynamic>>[];
        for (final it in items) {
          if (it is Map) {
            runningModels.add(Map<String, dynamic>.from(it));
          }
        }

        if (runningModels.isNotEmpty) {
          // Format running models with details
          final modelInfos = runningModels.map((model) {
            final name = model['name'] ?? model['model'] ?? 'Unknown';
            final size = model['size'];
            final sizeVram = model['size_vram'];
            final contextLength = model['context_length'];
            final details = model['details'] as Map<String, dynamic>?;

            final parts = <String>[name.toString()];

            if (details != null) {
              final paramSize = details['parameter_size'];
              final quantLevel = details['quantization_level'];
              if (paramSize != null) parts.add('${paramSize}');
              if (quantLevel != null) parts.add('${quantLevel}');
            }

            if (size != null) parts.add('${_humanSize(size)}');
            if (sizeVram != null) parts.add('VRAM: ${_humanSize(sizeVram)}');
            if (contextLength != null) parts.add('CTX: ${contextLength}');

            return parts.join(' • ');
          }).toList();

          running = modelInfos.join('\n');
        } else {
          running = null;
        }

        setState(() => _running = running);
      } else {
        setState(() => _running = null);
      }
    } catch (e) {
      setState(() => _running = null);
    }
  }

  String _displayName(Map<String, dynamic> m) {
    return (m['name'] ??
            m['model'] ??
            m['id'] ??
            m['tag'] ??
            m['title'] ??
            'Unnamed Model')
        .toString();
  }

  String _humanSize(dynamic value) {
    if (value == null) return '';
    int? bytes;
    if (value is int)
      bytes = value;
    else if (value is double)
      bytes = value.toInt();
    else if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) bytes = parsed;
    }
    if (bytes == null) return value.toString();

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double b = bytes.toDouble();
    int i = 0;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(b < 10 ? 2 : (b < 100 ? 1 : 0))} ${units[i]}';
  }

  // Try to find a numeric size field in the model map (shallow + nested one level)
  dynamic _findSizeField(Map<String, dynamic> m) {
    for (final k in m.keys) {
      final lk = k.toLowerCase();
      if (lk.contains('size') ||
          lk.contains('bytes') ||
          lk.contains('file_size')) {
        return m[k];
      }
    }
    // try nested maps
    for (final v in m.values) {
      if (v is Map) {
        for (final k2 in v.keys) {
          final lk2 = k2.toString().toLowerCase();
          if (lk2.contains('size') ||
              lk2.contains('bytes') ||
              lk2.contains('file_size')) {
            return v[k2];
          }
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('littleOllama'),
            Row(
              children: [
                // show only base URL (no path)
                Expanded(
                  child: Text(
                    _baseUrlFromEndpoint(),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_version != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      'v: $_version',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          // Theme chooser
          PopupMenuButton<ThemeMode>(
            icon: const Icon(Icons.brightness_6),
            onSelected: (m) async {
              await widget.onThemeChanged(m);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: ThemeMode.system,
                child: const Text('System'),
              ),
              PopupMenuItem(value: ThemeMode.light, child: const Text('Light')),
              PopupMenuItem(value: ThemeMode.dark, child: const Text('Dark')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Options',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => OptionsScreen(
                    currentEndpoint: _endpoint,
                    currentPollingInterval: _pollingInterval,
                    onEndpointChanged: (newEndpoint) async {
                      await storage.saveEndpoint(_prefsKeyEndpoint, newEndpoint);
                      _onEndpointChanged(newEndpoint);
                    },
                    onPollingIntervalChanged: _onPollingIntervalChanged,
                  ),
                ),
              );
            },
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Filter models (match any field)...',
                suffixIcon: _filterController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _filterController.clear();
                          setState(() {
                            _filter = '';
                          });
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          // running model info shown between filter and list
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.play_arrow, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Running Models:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh status',
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () async {
                        await _fetchVersion();
                        await _fetchRunning();
                      },
                    ),
                  ],
                ),
                if (_running == null)
                  const Text(
                    'No running models detected',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 26.0),
                    child: Text(
                      _running!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _futureModels,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 64,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text('Error: ${''}'),
                              const SizedBox(height: 8),
                              Text(snapshot.error.toString()),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _refresh,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  final models = snapshot.data ?? [];
                  final filter = _filter.trim().toLowerCase();
                  List<Map<String, dynamic>> filteredModels = models;
                  if (filter.isNotEmpty) {
                    filteredModels = models.where((m) {
                      // match against name first
                      final name = _displayName(m).toLowerCase();
                      if (name.contains(filter)) return true;
                      // match any field value
                      for (final v in m.values) {
                        if (v == null) continue;
                        if (v.toString().toLowerCase().contains(filter))
                          return true;
                      }
                      return false;
                    }).toList();
                  }

                  if (filteredModels.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 40),
                        Center(
                          child: Text(
                            filter.isEmpty
                                ? 'No models found'
                                : 'No models match "$filter"',
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filteredModels.length,
                    itemBuilder: (context, index) {
                      final model = filteredModels[index];
                      final name = _displayName(model);
                      final subtitle =
                          (model['description'] ?? model['summary'] ?? '')
                              .toString()
                              .trim();

                      final sizeVal = _findSizeField(model);
                      final sizeText = sizeVal != null
                          ? _humanSize(sizeVal)
                          : null;

                      return Card(
                        child: ExpansionTile(
                          key: ValueKey('expansion-$name-$index'),
                          title: Row(
                            children: [
                              Expanded(child: Text(name)),
                              if (sizeText != null)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    sizeText,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                          children: model.entries.map((entry) {
                            final k = entry.key;
                            final v = entry.value;
                            if (v is Map || v is List) {
                              final pretty = const JsonEncoder.withIndent(
                                '  ',
                              ).convert(v);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: SelectableText(
                                  pretty,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              );
                            }

                            final lk = k.toLowerCase();
                            if (lk.contains('size') ||
                                lk.contains('bytes') ||
                                lk.contains('file_size')) {
                              return ListTile(
                                title: Text(k),
                                subtitle: Text(
                                  v == null
                                      ? 'null'
                                      : '${v.toString()} (${_humanSize(v)})',
                                ),
                              );
                            }

                            return ListTile(
                              title: Text(k),
                              subtitle: Text(v == null ? 'null' : v.toString()),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
