// models/settings.dart
class Settings {
  final int healthCheckInterval;
  final bool notificationsEnabled;

  Settings({
    required this.healthCheckInterval,
    bool? notificationsEnabled,  // Make it nullable in constructor
  }) : notificationsEnabled = notificationsEnabled ?? true;  // Default to true if null

  Map<String, dynamic> toJson() => {
    'healthCheckInterval': healthCheckInterval,
    'notificationsEnabled': notificationsEnabled,
  };

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      healthCheckInterval: json['healthCheckInterval'] ?? 10,
      notificationsEnabled: json['notificationsEnabled'],  // Let constructor handle default
    );
  }
}