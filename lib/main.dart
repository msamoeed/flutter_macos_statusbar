import 'package:flutter/material.dart';
import 'package:flutter_statusbar_app/models/settings.dart';
import 'package:flutter_statusbar_app/networking/api.dart';
import 'package:flutter_statusbar_app/screens/settings.dart';
import 'package:localstore/localstore.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

// Initialize notifications plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications only for macOS
  if (!kIsWeb && Platform.isMacOS) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        macOS: DarwinInitializationSettings(
          defaultPresentAlert: true,
          defaultPresentBadge: true,
          defaultPresentSound: true,
        ),
      ),
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'cURL Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'cURL Monitor'),
    );
  }
}

class CurlStatus {
  final String id;
  final String name;
  final String curl;
  bool isHealthy;
  bool wasHealthy; // Track previous state for notification logic

  CurlStatus({
    required this.id,
    required this.name,
    required this.curl,
    this.isHealthy = false,
    this.wasHealthy = false,
  });
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _db = Localstore.instance;
  final List<CurlStatus> _curls = [];
  final _curlController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Timer? _healthCheckTimer;
  late Settings _settings;
  Future<void> _showNotification(String name, String message) async {
    if (!kIsWeb && Platform.isMacOS) {
      await flutterLocalNotificationsPlugin.show(
        0,
        'cURL Monitor Alert',
        '$name: $message',
        const NotificationDetails(macOS: DarwinNotificationDetails()),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _settings = Settings(healthCheckInterval: 10);
    _loadSettings();
    _loadCurls();

    _startHealthCheck();
  }

  Future<void> _loadSettings() async {
    final prefs = await _db.collection('settings').doc('general').get();
    if (prefs != null) {
      setState(() {
        _settings = Settings.fromJson(prefs);
      });
    }
    _startHealthCheck();
  }

  Future<void> _saveSettings(Settings newSettings) async {
    await _db.collection('settings').doc('general').set(newSettings.toJson());
    setState(() {
      _settings = newSettings;
    });
    _startHealthCheck();
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      Duration(seconds: _settings.healthCheckInterval),
      (_) => _checkAllCurlsHealth(),
    );
  }

  Future<void> _checkAllCurlsHealth() async {
    for (var curl in _curls) {
      await _checkCurlHealth(curl);
    }
  }

  Future<void> _checkCurlHealth(CurlStatus curlStatus) async {
    try {
      final response = await CurlDioConverter.executeCurl(curlStatus.curl);
      final isHealthy = response.statusCode == 200;

      if (mounted) {
        setState(() {
          curlStatus.wasHealthy = curlStatus.isHealthy;
          curlStatus.isHealthy = isHealthy;
        });

        // Show notification only when status changes to unhealthy
        if (!isHealthy && _settings.notificationsEnabled) {
          await _showNotification(
            curlStatus.name,
            'Status changed to unhealthy (${response.statusCode})',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          curlStatus.wasHealthy = curlStatus.isHealthy;
          curlStatus.isHealthy = false;
        });

        // Show notification for errors only when status changes
        if (curlStatus.wasHealthy) {
          await _showNotification(
            curlStatus.name,
            'Error: ${e.toString()}',
          );
        }
      }
    }
  }

  void _loadCurls() async {
    final items = await _db.collection('curls').get();
    if (items != null) {
      final List<CurlStatus> loadedCurls = items.entries.map((item) {
        return CurlStatus(
          id: item.key,
          name: item.value['name'],
          curl: item.value['curl'],
        );
      }).toList();

      setState(() {
        _curls.clear();
        _curls.addAll(loadedCurls);
      });

      // Initial health check
      _checkAllCurlsHealth();
    }
  }

  Future<void> _saveCurl(String name, String curl) async {
    final id = _db.collection('curls').doc().id;
    final data = {
      'name': name,
      'curl': curl,
    };

    await _db.collection('curls').doc(id).set(data);

    final newCurl = CurlStatus(
      id: id,
      name: name,
      curl: curl,
    );

    setState(() {
      _curls.add(newCurl);
    });

    // Check health immediately after adding
    await _checkCurlHealth(newCurl);
  }

  Future<void> _deleteCurl(String id) async {
    await _db.collection('curls').doc(id).delete();

    setState(() {
      _curls.removeWhere((curl) => curl.id == id);
    });
  }

  void _showAddCurlSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _curlController,
                  decoration: const InputDecoration(
                    labelText: 'cURL Command',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a cURL command';
                    }
                    if (!value.trim().toLowerCase().startsWith('curl')) {
                      return 'Command must start with "curl"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      await _saveCurl(
                        _nameController.text,
                        _curlController.text,
                      );
                      _nameController.clear();
                      _curlController.clear();
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsPage(
                    settings: _settings,
                    onSettingsChanged: _saveSettings,
                  ),
                ),
              );
              if (result == true) {
                _loadCurls();
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _curls.length,
        itemBuilder: (context, index) {
          final curl = _curls[index];
          return ListTile(
            leading: Icon(
              Icons.circle,
              color: curl.isHealthy ? Colors.green : Colors.red,
              size: 16,
            ),
            title: Text(curl.name),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _deleteCurl(curl.id),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(curl.name),
                  content: SelectableText(curl.curl),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCurlSheet,
        tooltip: 'Add cURL',
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _curlController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
