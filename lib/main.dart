import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/ollama_models.dart';
import 'screens/options_screen.dart';
import 'services/ollama_service.dart';
import 'src/storage_io.dart' if (dart.library.html) 'src/storage_web.dart' as storage;
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
    final v = await storage.loadSetting(_prefsThemeKey) ?? 'system';
    setState(() {
      if (v == 'light') {
        _themeMode = ThemeMode.light;
      } else if (v == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.system;
      }
    });
  }

  Future<void> _setThemeMode(ThemeMode m) async {
    final s = m == ThemeMode.light ? 'light' : (m == ThemeMode.dark ? 'dark' : 'system');
    await storage.saveSetting(_prefsThemeKey, s);
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
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

  const ModelsPage({super.key, required this.themeMode, required this.onThemeChanged});

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
    final stored = await storage.loadSetting(_prefsKeyEndpoint);
    if (stored != null && stored.isNotEmpty) {
      _endpoint = AppUtils.normalizeEndpoint(stored);
    }
    // Load polling interval
    final pollingStr = await storage.loadSetting(_prefsKeyPollingInterval);
    if (pollingStr != null) {
      _pollingInterval = int.tryParse(pollingStr) ?? 0;
    }
    // Load sort option
    final sortStr = await storage.loadSetting(_prefsKeySortBy);
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
            const Text('LittleOllama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            if (_version != null)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  'Ollama v$_version ${AppUtils.baseUrlFromEndpoint(_endpoint)}',
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
              PopupMenuItem(value: ThemeMode.system, child: const Text('System')),
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
                      await storage.saveSetting(_prefsKeyEndpoint, newEndpoint);
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
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.play_arrow, size: 18),
                    const SizedBox(width: 8),
                    const Text('Running Models:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                  const Text('No running models detected', style: TextStyle(fontSize: 13, color: Colors.grey))
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 26.0),
                    child: Text(_running!, style: const TextStyle(fontSize: 13)),
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
                                child: Card(
                                  color: Theme.of(context).colorScheme.errorContainer,
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Failed to load models',
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onErrorContainer),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.refresh),
                                          onPressed: _refresh,
                                          label: const Text('Retry'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Theme.of(context).colorScheme.error,
                                            foregroundColor: Theme.of(context).colorScheme.onError,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                            if (m.model?.toLowerCase().contains(filter) == true) return true;
                            if (m.parameterSize?.toLowerCase().contains(filter) == true) return true;
                            if (m.quantizationLevel?.toLowerCase().contains(filter) == true) return true;
                            return false;
                          }).toList();
                        }
                        // Sort models by selected option
                        filteredModels.sort((a, b) {
                          switch (_sortBy) {
                            case 'modified_at':
                              return (a.modifiedAt ?? '').compareTo(b.modifiedAt ?? '');
                            case 'size':
                              return (b.size ?? 0).compareTo(a.size ?? 0);
                            case 'family':
                              return (a.details?['family'] ?? '').compareTo(b.details?['family'] ?? '');
                            case 'name':
                            default:
                              return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                          }
                        });

                        if (filteredModels.isEmpty) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 40),
                              Center(child: Text(filter.isEmpty ? 'No models found' : 'No models match "$filter"')),
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
                                              style: TextStyle(color: chipFg, fontSize: 10),
                                            ),
                                            visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                subtitle: null,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Digest
                                        if (model.digest != null)
                                          Row(
                                            children: [
                                              const Icon(Icons.fingerprint, size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: SelectableText(
                                                  model.digest!,
                                                  style: const TextStyle(fontSize: 13),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.copy, size: 16),
                                                tooltip: 'Copy digest',
                                                onPressed: () {
                                                  Clipboard.setData(ClipboardData(text: model.digest!));
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Digest copied!')),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        // Size
                                        if (model.size != null)
                                          Row(
                                            children: [
                                              const Icon(Icons.storage, size: 18),
                                              const SizedBox(width: 8),
                                              Text(
                                                AppUtils.humanSize(model.size),
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(width: 8),
                                              Text('(${model.size})', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                            ],
                                          ),
                                        // Details chips
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            if (model.details?['family'] != null)
                                              Chip(
                                                label: Text('Family: ${model.details!['family']}'),
                                                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                                              ),
                                            if (model.details?['quantization_level'] != null)
                                              Chip(
                                                label: Text('Quant: ${model.details!['quantization_level']}'),
                                                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                                              ),
                                            if (model.details?['parameter_size'] != null)
                                              Chip(
                                                label: Text('Params: ${model.details!['parameter_size']}'),
                                                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                                              ),
                                            if (model.details?['format'] != null)
                                              Chip(
                                                label: Text('Format: ${model.details!['format']}'),
                                                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                                              ),
                                          ],
                                        ),
                                        // Placeholder for extra info (to be filled after POST)
                                        ModelExtraInfoWidget(modelName: model.displayName, ollamaService: _ollamaService!),
                                      ],
                                    ),
                                  ),
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

class ModelExtraInfoWidget extends StatefulWidget {
  final String modelName;
  final OllamaService ollamaService;

  const ModelExtraInfoWidget({super.key, required this.modelName, required this.ollamaService});

  @override
  State<ModelExtraInfoWidget> createState() => _ModelExtraInfoWidgetState();
}

class _ModelExtraInfoWidgetState extends State<ModelExtraInfoWidget> {
  Map<String, dynamic>? _extraInfo;
  bool _loading = false;
  String? _error;
  bool _expandedModelfile = false;
  bool _expandedParameters = false;
  bool _expandedTemplate = false;

  @override
  void initState() {
    super.initState();
    _fetchExtraInfo();
  }

  Future<void> _fetchExtraInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.ollamaService.fetchModelExtraInfo(widget.modelName);
      setState(() {
        _extraInfo = info;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Widget _buildCollapsibleSection(String title, String? content, bool expanded, void Function(bool) onChanged) {
    if (content == null || content.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        initiallyExpanded: expanded,
        onExpansionChanged: onChanged,
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceVariant,
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title copied!')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_extraInfo == null) {
      return const SizedBox.shrink();
    }
    final details = _extraInfo!['details'] as Map<String, dynamic>?;
    final modelInfo = _extraInfo!['model_info'] as Map<String, dynamic>?;
    final capabilities = (_extraInfo!['capabilities'] as List?)?.cast<String>() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCollapsibleSection('Modelfile', _extraInfo!['modelfile'] as String?, _expandedModelfile, (v) => setState(() => _expandedModelfile = v)),
        _buildCollapsibleSection('Parameters', _extraInfo!['parameters'] as String?, _expandedParameters, (v) => setState(() => _expandedParameters = v)),
        _buildCollapsibleSection('Template', _extraInfo!['template'] as String?, _expandedTemplate, (v) => setState(() => _expandedTemplate = v)),
        if (details != null && details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Details', style: TextStyle(fontWeight: FontWeight.bold)),
                ...details.entries.where((e) => !((e.key == 'parent_model' || e.key == 'families') && (e.value == null || (e.value is String && e.value.isEmpty)))).map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13, color: Colors.grey))),
                      const SizedBox(width: 8),
                      Expanded(child: SelectableText(e.value.toString(), style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
              ],
            ),
          ),
        if (modelInfo != null && modelInfo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Model Info', style: TextStyle(fontWeight: FontWeight.bold)),
                ...modelInfo.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13, color: Colors.grey))),
                      const SizedBox(width: 8),
                      Expanded(child: SelectableText(e.value.toString(), style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
              ],
            ),
          ),
        if (capabilities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              spacing: 8,
              children: capabilities.map((c) => Chip(
                label: Text(c),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              )).toList(),
            ),
          ),
      ],
    );
  }
}
