import 'dart:async';

import 'package:flutter/material.dart';
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
      if (v == 'light') {
        _themeMode = ThemeMode.light;
      } else if (v == 'dark')
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
  Future<List<OllamaModel>>? _futureModels;
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  static const _prefsKeyEndpoint = 'ollama_endpoint';
  static const _prefsKeyPollingInterval = 'polling_interval';
  String? _version;
  String? _running;
  Timer? _pollingTimer;
  int _pollingInterval = 0; // 0 = manual only
  OllamaService? _ollamaService;
  String _sortBy = 'name';
  static const _prefsKeySortBy = 'model_sort_by';

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
      _endpoint = AppUtils.normalizeEndpoint(stored);
    }
    // Load polling interval
    final pollingStr = await storage.loadTheme(_prefsKeyPollingInterval);
    if (pollingStr != null) {
      _pollingInterval = int.tryParse(pollingStr) ?? 0;
    }
    // Load sort option
    final sortStr = await storage.loadTheme(_prefsKeySortBy);
    if (sortStr != null && sortStr.isNotEmpty) {
      _sortBy = sortStr;
    }
    _ollamaService = OllamaService(AppUtils.baseUrlFromEndpoint(_endpoint));
    setState(() {
      _futureModels = _ollamaService!.fetchModels();
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
      _ollamaService = OllamaService(AppUtils.baseUrlFromEndpoint(newEndpoint));
      _futureModels = _ollamaService!.fetchModels();
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

  void _onSortByChanged(String newSortBy) {
    setState(() {
      _sortBy = newSortBy;
    });
  }

  Future<void> _refresh() async {
    if (_ollamaService != null) {
      setState(() {
        _futureModels = _ollamaService!.fetchModels();
      });
      await _futureModels;
    }
    await _fetchVersion();
    await _fetchRunning();
  }

  Future<void> _fetchVersion() async {
    if (_ollamaService != null) {
      final version = await _ollamaService!.fetchVersion();
      setState(() => _version = version);
    }
  }

  Future<void> _fetchRunning() async {
    if (_ollamaService != null) {
      final runningModels = await _ollamaService!.fetchRunningModels();
      if (runningModels.isNotEmpty) {
        final modelInfos = runningModels.map((model) => model.formatDetails(AppUtils.humanSize)).toList();
        setState(() => _running = modelInfos.join('\n'));
      } else {
        setState(() => _running = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LittleOllama',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (_version != null)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  'Ollama v: $_version ${AppUtils.baseUrlFromEndpoint(_endpoint)}',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
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
                    currentSortBy: _sortBy,
                    onEndpointChanged: (newEndpoint) async {
                      await storage.saveEndpoint(_prefsKeyEndpoint, newEndpoint);
                      _onEndpointChanged(newEndpoint);
                    },
                    onPollingIntervalChanged: _onPollingIntervalChanged,
                    onSortByChanged: _onSortByChanged,
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
          // running model info shown between appbar and filter
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
          // filter box below running models
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _futureModels == null
                  ? const Center(child: CircularProgressIndicator())
                  : FutureBuilder<List<OllamaModel>>(
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
                  List<OllamaModel> filteredModels = models;
                  if (filter.isNotEmpty) {
                    filteredModels = models.where((m) {
                      // match against name first
                      final name = m.displayName.toLowerCase();
                      if (name.contains(filter)) return true;
                      // match model field or other details
                      if (m.model?.toLowerCase().contains(filter) ?? false) return true;
                      if (m.parameterSize?.toLowerCase().contains(filter) ?? false) return true;
                      if (m.quantizationLevel?.toLowerCase().contains(filter) ?? false) return true;
                      return false;
                    }).toList();
                  }
                  // Sort models by selected option
                  filteredModels.sort((a, b) {
                    switch (_sortBy) {
                      case 'name':
                        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                      case 'modified_at':
                        return (a.modifiedAt ?? '').compareTo(b.modifiedAt ?? '');
                      case 'size':
                        return (b.size ?? 0).compareTo(a.size ?? 0);
                      case 'family':
                        return (a.details?['family'] ?? '').compareTo(b.details?['family'] ?? '');
                      default:
                        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                    }
                  });

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
                      final name = model.displayName;
                      final sizeText = model.size != null ? AppUtils.humanSize(model.size) : null;
                      final chipBg = Theme.of(context).colorScheme.surfaceContainerHighest;
                      final chipFg = Theme.of(context).colorScheme.onSurfaceVariant;

                      return Card(
                        elevation: 3,
                        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ExpansionTile(
                          key: ValueKey('expansion-$name-$index'),
                          title: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (sizeText != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4.0),
                                    child: Chip(
                                      backgroundColor: chipBg,
                                      label: Text(
                                        sizeText,
                                        style: TextStyle(color: chipFg, fontSize: 10), // smaller text
                                      ),
                                      visualDensity: VisualDensity(horizontal: -4, vertical: -4), // smaller chip
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                    ),
                                  ),
                                // Removed parameterSize chip
                              ],
                            ),
                          ),
                          subtitle: null,
                          children: [
                            if (model.digest != null)
                              ListTile(
                                title: const Text('Digest'),
                                subtitle: Text(model.digest!),
                              ),
                            if (model.size != null)
                              ListTile(
                                title: const Text('Size'),
                                subtitle: Text('${model.size} (${AppUtils.humanSize(model.size)})'),
                              ),
                            if (model.sizeVram != null)
                              ListTile(
                                title: const Text('VRAM Size'),
                                subtitle: Text('${model.sizeVram} (${AppUtils.humanSize(model.sizeVram)})'),
                              ),
                            if (model.contextLength != null)
                              ListTile(
                                title: const Text('Context Length'),
                                subtitle: Text(model.contextLength.toString()),
                              ),
                            if (model.expiresAt != null)
                              ListTile(
                                title: const Text('Expires At'),
                                subtitle: Text(model.expiresAt.toString()),
                              ),

                            // Render details map as individual properties (not raw JSON)
                            if (model.details != null) ...[
                              const Divider(),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Text('Details', style: Theme.of(context).textTheme.titleSmall),
                              ),
                              for (final entry in model.details!.entries)
                                ListTile(
                                  dense: true,
                                  title: Text(entry.key),
                                  subtitle: Text(
                                    entry.value == null
                                        ? 'null'
                                        : (entry.value is Map || entry.value is List)
                                            ? (model.detailsPretty ?? entry.value.toString())
                                            : entry.value.toString(),
                                  ),
                                ),
                            ],
                          ],
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
