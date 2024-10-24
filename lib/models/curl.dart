class CurlStatus {
  final String id;
  final String name;
  final String curl;
  final String endpoint;
  bool isHealthy;
  bool wasHealthy; // Track previous state for notification logic

  CurlStatus({
    required this.endpoint,
    required this.id,
    required this.name,
    required this.curl,
    this.isHealthy = false,
    this.wasHealthy = false,
  });
}