import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'src/storage_io.dart' if (dart.library.html) 'src/storage_web.dart' as storage;

class OptionsScreen extends StatefulWidget {
  final String currentEndpoint;
  final int currentPollingInterval;
  final Function(String) onEndpointChanged;
  final Function(int) onPollingIntervalChanged;

  const OptionsScreen({
    super.key,
    required this.currentEndpoint,
    required this.currentPollingInterval,
    required this.onEndpointChanged,
    required this.onPollingIntervalChanged,
  });

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  late TextEditingController _endpointController;
  late int _pollingInterval;
  PackageInfo? _packageInfo;

  static const _prefsKeyPollingInterval = 'polling_interval';

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(text: widget.currentEndpoint);
    _pollingInterval = widget.currentPollingInterval;
    _loadPackageInfo();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  Future<void> _saveSettings() async {
    final endpoint = _endpointController.text.trim();
    
    // Normalize endpoint
    var normalizedEndpoint = endpoint;
    if (normalizedEndpoint.contains('/api/')) {
      normalizedEndpoint = normalizedEndpoint.split('/api/')[0];
    }
    if (!normalizedEndpoint.startsWith('http://') && !normalizedEndpoint.startsWith('https://')) {
      normalizedEndpoint = 'http://$normalizedEndpoint';
    }

    // Save polling interval
    await storage.saveTheme(_prefsKeyPollingInterval, _pollingInterval.toString());

    // Call callbacks
    widget.onEndpointChanged(normalizedEndpoint);
    widget.onPollingIntervalChanged(_pollingInterval);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Options'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // App Version Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'littleOllama ${_packageInfo?.version ?? 'Unknown'}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  if (_packageInfo?.buildNumber != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Build: ${_packageInfo!.buildNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Server Configuration Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Server Configuration',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _endpointController,
                    decoration: const InputDecoration(
                      labelText: 'Ollama Server URL',
                      hintText: 'http://localhost:11434',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                      helperText: 'Enter the base URL of your Ollama server',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Polling Configuration Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Polling Configuration',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 20),
                      const SizedBox(width: 8),
                      const Text('Refresh interval for running models:'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      RadioListTile<int>(
                        title: const Text('Manual only'),
                        subtitle: const Text('Only refresh when manually triggered'),
                        value: 0,
                        groupValue: _pollingInterval,
                        onChanged: (value) {
                          setState(() {
                            _pollingInterval = value!;
                          });
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('Every 5 seconds'),
                        value: 5,
                        groupValue: _pollingInterval,
                        onChanged: (value) {
                          setState(() {
                            _pollingInterval = value!;
                          });
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('Every 10 seconds'),
                        value: 10,
                        groupValue: _pollingInterval,
                        onChanged: (value) {
                          setState(() {
                            _pollingInterval = value!;
                          });
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('Every 30 seconds'),
                        value: 30,
                        groupValue: _pollingInterval,
                        onChanged: (value) {
                          setState(() {
                            _pollingInterval = value!;
                          });
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('Every minute'),
                        value: 60,
                        groupValue: _pollingInterval,
                        onChanged: (value) {
                          setState(() {
                            _pollingInterval = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
