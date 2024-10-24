import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_statusbar_app/main.dart';
import 'package:flutter_statusbar_app/models/settings.dart';
import 'package:localstore/localstore.dart';

class SettingsPage extends StatefulWidget {
  final Settings settings;
  final Function(Settings) onSettingsChanged;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _intervalController;
  final _db = Localstore.instance;
  late bool _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: widget.settings.healthCheckInterval.toString(),
    );
    _notificationsEnabled = widget.settings.notificationsEnabled;
  }

  Future<void> _updateInterval(String value) async {
    final interval = int.tryParse(value) ?? 10;

    try {
      final settings = {
        'healthCheckInterval': interval,
        'notificationsEnabled': _notificationsEnabled,
      };

      await _db.collection('settings').doc('general').set(settings);

      widget.onSettingsChanged(
        Settings(
          healthCheckInterval: interval,
          notificationsEnabled: _notificationsEnabled,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save interval: ${e.toString()}')),
        );
      }
    }
  }

  // Add this new method to clean the database
  Future<void> _cleanDatabase() async {
    try {
      // Delete all CURLs
      final curls = await _db.collection('curls').get();
      if (curls != null) {
        for (var key in curls.keys) {
          await _db.collection('curls').doc(key).delete();
        }
      }

      // Delete settings
      await _db.collection('settings').doc('general').delete();

      // Delete endpoint stats if you have any
      final stats = await _db.collection('endpoint_stats').get();
      if (stats != null) {
        for (var key in stats.keys) {
          await _db.collection('endpoint_stats').doc(key).delete();
        }
      }
    } catch (e) {
      throw Exception('Failed to clean database: $e');
    }
  }

  Future<void> _updateNotifications(bool value) async {
    try {
      if (value && !kIsWeb && Platform.isMacOS) {
        final bool? permissionGranted = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
        if (permissionGranted != true) {
          // Permission not granted, don't enable notifications
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notification permission denied')),
          );
          return;
        }
      }

      setState(() {
        _notificationsEnabled = value;
      });

      final settings = {
        'healthCheckInterval': int.tryParse(_intervalController.text) ?? 10,
        'notificationsEnabled': value,
      };

      await _db.collection('settings').doc('general').set(settings);

      widget.onSettingsChanged(
        Settings(
          healthCheckInterval: int.tryParse(_intervalController.text) ?? 10,
          notificationsEnabled: value,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update notifications: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Health Check Settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Health check interval (seconds)',
                  border: OutlineInputBorder(),
                  helperText: 'Changes are saved automatically',
                ),
                onChanged: _updateInterval,
              ),
              const SizedBox(height: 24),
              const Text(
                'Notification Settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Enable Notifications'),
                subtitle: const Text('Show alerts when status changes'),
                value: _notificationsEnabled,
                onChanged: _updateNotifications,
              ),
              const SizedBox(height: 32),
              const Text(
                'Import/Export',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.saveFile(
                          dialogTitle: 'Save cURLs and Settings',
                          fileName: 'curls_export.json',
                          // allowedExtensions: ['json'],
                        );

                        if (result != null) {
                          final file = File(result);
                          final db = Localstore.instance;

                          final curls = await db.collection('curls').get();
                          final settings = await db
                              .collection('settings')
                              .doc('general')
                              .get();

                          final exportData = {
                            'curls': curls,
                            'settings': settings ??
                                {
                                  'healthCheckInterval': 10,
                                  'notificationsEnabled': true,
                                }, // Use defaults if no settings exist
                          };

                          await file.writeAsString(jsonEncode(exportData));

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Export completed')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Export cURLs'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          allowMultiple: false,
                          dialogTitle: 'Import cURLs and Settings',

                          // allowedExtensions: ['json'],
                          // type: FileType.custom,
                        );

                        if (result != null) {
                          try {
                            // await _cleanDatabase();
                            final file = File(result.files.single.path!);
                            final content = await file.readAsString();
                            final data =
                                jsonDecode(content) as Map<String, dynamic>;

                            if (data['settings'] != null) {
                              await _db
                                  .collection('settings')
                                  .doc('general')
                                  .set(data['settings']);

                              setState(() {
                                if (data['settings']['healthCheckInterval'] !=
                                    null) {
                                  _intervalController.text = data['settings']
                                          ['healthCheckInterval']
                                      .toString();
                                }
                                // Handle potential null notification setting
                                _notificationsEnabled = data['settings']
                                        ['notificationsEnabled'] ??
                                    true;
                              });

                              widget.onSettingsChanged(Settings(
                                healthCheckInterval: data['settings']
                                        ['healthCheckInterval'] ??
                                    10,
                                notificationsEnabled: data['settings']
                                    ['notificationsEnabled'],
                              ));
                            }

                            if (data['curls'] != null) {
                              final curlsData =
                                  data['curls'] as Map<String, dynamic>;
                              for (var entry in curlsData.entries) {
                                await _db
                                    .collection('curls')
                                    .doc(entry.key)
                                    .set(entry.value);
                              }
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Import completed')),
                              );
                              Navigator.pop(context, true);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Import failed: ${e.toString()}')),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.upload),
                      label: const Text('Import cURLs'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }
}
