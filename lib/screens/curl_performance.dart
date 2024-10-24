import 'package:flutter/material.dart';
import 'package:chart_sparkline/chart_sparkline.dart';
import 'package:flutter_statusbar_app/logging/logging_interceptor.dart';

class ApiPerformanceGraph extends StatelessWidget {
  final RequestStats stats;
  final String endpointPath;

  const ApiPerformanceGraph({
    Key? key,
    required this.stats,
    required this.endpointPath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'API Performance - $endpointPath',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildResponseTimeGraph(),
            const SizedBox(height: 24),
            _buildSuccessRateGraph(),
            const SizedBox(height: 16),
            _buildStats(),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseTimeGraph() {
    // Extract response times from recent logs
    final responseTimes = stats.recentLogs
        .map((log) => log.responseTimeMs.toDouble())
        .toList()
        .reversed
        .toList();

    if (responseTimes.isEmpty) {
      return const Center(child: Text('No response time data available'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Response Times (last ${responseTimes.length} requests)'),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: Sparkline(
            data: responseTimes,
            lineColor: Colors.blue,
            pointsMode: PointsMode.all,
            pointSize: 5.0,
            pointColor: Colors.blueAccent,
            useCubicSmoothing: true,
            cubicSmoothingFactor: 0.2,
            averageLine: true,
            averageLabel: true,
           
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Min: ${responseTimes.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}ms'),
            Text('Max: ${responseTimes.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}ms'),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessRateGraph() {
    // Calculate success rate over time
    final successRates = <double>[];
    int successCount = 0;
    int totalCount = 0;
    
    for (var log in stats.recentLogs.reversed) {
      totalCount++;
      if (log.error == null && log.statusCode >= 200 && log.statusCode < 300) {
        successCount++;
      }
      successRates.add((successCount / totalCount) * 100);
    }

    if (successRates.isEmpty) {
      return const Center(child: Text('No success rate data available'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Success Rate Trend (last ${successRates.length} requests)'),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: Sparkline(
            data: successRates,
            lineColor: Colors.green,
            pointsMode: PointsMode.all,
            pointSize: 5.0,
            pointColor: Colors.greenAccent,
            sharpCorners: true,
            averageLine: true,
            averageLabel: true,
         
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    final successRate = (stats.successfulRequests / stats.totalRequests * 100);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text('Total Requests: ${stats.totalRequests}'),
        Text('Success Rate: ${successRate.toStringAsFixed(1)}%'),
        Text('Average Response Time: ${stats.averageResponseTimeMs.toStringAsFixed(1)}ms'),
        Text('Last Request: ${_formatTimestamp(stats.lastAccessTime)}'),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
