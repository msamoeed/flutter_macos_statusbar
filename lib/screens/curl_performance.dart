import 'package:chart_sparkline/chart_sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_statusbar_app/logging/logging_interceptor.dart';
import 'package:localstore/localstore.dart';
import 'package:intl/intl.dart';

class CurlPerformanceScreen extends StatefulWidget {
  final String curl;
  final String name;

  const CurlPerformanceScreen({
    super.key,
    required this.curl,
    required this.name,
  });

  @override
  State<CurlPerformanceScreen> createState() => _CurlPerformanceScreenState();
}

class _CurlPerformanceScreenState extends State<CurlPerformanceScreen> {
  final _db = Localstore.instance;
  List<LogEntry> _logs = [];
  bool _isLoading = true;
  String _timeRange = '1h';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final logs = await _db.collection('curl_logs').get();
      if (logs != null) {
        final DateTime cutoff = _getTimeRangeCutoff();

        final entries = logs.entries
            .map((e) => LogEntry.fromJson(e.value))
            .where((log) =>
                log.curl == widget.curl && log.timestamp.isAfter(cutoff))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        setState(() {
          _logs = entries;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load logs: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  DateTime _getTimeRangeCutoff() {
    final now = DateTime.now();
    switch (_timeRange) {
      case '10sec':
        return now.subtract(const Duration(seconds: 10));
      case '1h':
        return now.subtract(const Duration(hours: 1));
      case '24h':
        return now.subtract(const Duration(hours: 24));
      case '7d':
        return now.subtract(const Duration(days: 7));
      case '30d':
        return now.subtract(const Duration(days: 30));
      default:
        return now.subtract(const Duration(hours: 1));
    }
  }

  String _getTimeRangeLabel() {
    switch (_timeRange) {
      case '1h':
        return 'Last Hour';
      case '24h':
        return 'Last 24 Hours';
      case '7d':
        return 'Last 7 Days';
      case '30d':
        return 'Last 30 Days';
      default:
        return 'Last Hour';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Performance: ${widget.name}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (String value) {
              setState(() {
                _timeRange = value;
              });
              _loadLogs();
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: '1h',
                child: Text('Last Hour'),
              ),
              const PopupMenuItem(
                value: '24h',
                child: Text('Last 24 Hours'),
              ),
              const PopupMenuItem(
                value: '7d',
                child: Text('Last 7 Days'),
              ),
              const PopupMenuItem(
                value: '30d',
                child: Text('Last 30 Days'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('No performance data available'))
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTimeRangeChip(),
                        const SizedBox(height: 8),
                        _buildPerformanceGraph(),
                        const SizedBox(height: 24),
                        Text(
                          'Statistics',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        _buildStatistics(),
                        const SizedBox(height: 24),
                        Text(
                          'Recent Calls',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        _buildLogList(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildTimeRangeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        _getTimeRangeLabel(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildPerformanceGraph() {
    final responseTimes =
        _logs.map((e) => e.responseTimeMs.toDouble()).toList();
    final maxTime = responseTimes.reduce((a, b) => a > b ? a : b);
    final minTime = responseTimes.reduce((a, b) => a < b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Response Times',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: Sparkline(
                data: responseTimes,
                lineWidth: 2.0,
                lineColor: Theme.of(context).colorScheme.primary,
                pointsMode: PointsMode.all,
                pointSize: 4.0,
                pointColor: Theme.of(context).colorScheme.primary,
                useCubicSmoothing: true,
                cubicSmoothingFactor: 0.2,
                sharpCorners: false,
                fillMode: FillMode.below,
                fillGradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    Theme.of(context).colorScheme.primary.withOpacity(0.0),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Min: ${minTime.toStringAsFixed(0)}ms'),
                Text('Max: ${maxTime.toStringAsFixed(0)}ms'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    if (_logs.isEmpty) return const SizedBox.shrink();

    final responseTimes = _logs.map((e) => e.responseTimeMs).toList();
    final avg = responseTimes.reduce((a, b) => a + b) / responseTimes.length;
    final min = responseTimes.reduce((a, b) => a < b ? a : b);
    final max = responseTimes.reduce((a, b) => a > b ? a : b);
    final successRate = (_logs.where((log) => log.statusCode == 200).length /
            _logs.length *
            100)
        .toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatRow(
              'Average Response Time',
              '${avg.toStringAsFixed(1)}ms',
            ),
            const Divider(),
            _buildStatRow(
              'Fastest Response',
              '${min}ms',
            ),
            const Divider(),
            _buildStatRow(
              'Slowest Response',
              '${max}ms',
            ),
            const Divider(),
            _buildStatRow(
              'Success Rate',
              '$successRate%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        final success = log.statusCode == 200;
        final dateFormat = DateFormat('MMM d, HH:mm:ss');

        return Card(
          child: ListTile(
            leading: Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
            ),
            title: Text('${log.responseTimeMs}ms'),
            subtitle: Text(dateFormat.format(log.timestamp)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: success
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${log.statusCode}',
                style: TextStyle(
                  color: success ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
