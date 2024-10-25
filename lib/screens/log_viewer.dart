import 'package:flutter/material.dart';
import 'package:flutter_statusbar_app/logging/logging_interceptor.dart';
import 'package:flutter_statusbar_app/screens/curl_performance.dart';
import 'package:localstore/localstore.dart';

enum TimeRangeFilter {
  last24Hours('Last 24 Hours'),
  last3Days('Last 3 Days'),
  last7Days('Last 7 Days'),
  last30Days('Last 30 Days'),
  all('All Time');

  final String label;
  const TimeRangeFilter(this.label);
}

enum StatusFilter {
  all('All Status'),
  success('Success'),
  error('Error');

  final String label;
  const StatusFilter(this.label);
}

class LogViewer extends StatefulWidget {
  final String endpointPath;
  final Duration timeRange;

  const LogViewer({
    Key? key,
    required this.endpointPath,
    this.timeRange = const Duration(days: 7),
  }) : super(key: key);

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  final _db = Localstore.instance;
  List<LogEntry> _logs = [];
  bool _isLoading = false;
  RequestStats? _endpointStats;
  
  // Filter states
  TimeRangeFilter _selectedTimeRange = TimeRangeFilter.last7Days;
  StatusFilter _selectedStatus = StatusFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();


  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
               // mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Logs',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TimeRangeFilter>(
                    value: _selectedTimeRange,
                    decoration: const InputDecoration(
                      labelText: 'Time Range',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: TimeRangeFilter.values.map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedTimeRange = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<StatusFilter>(
                    value: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: StatusFilter.values.map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedStatus = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search',
                      hintText: 'Search in request/response data',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedTimeRange = TimeRangeFilter.last7Days;
                            _selectedStatus = StatusFilter.all;
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                        child: const Text('Reset'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _loadLogs();
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _getTimeRangeCutoff() {
    switch (_selectedTimeRange) {
      case TimeRangeFilter.last24Hours:
        return DateTime.now().subtract(const Duration(hours: 24));
      case TimeRangeFilter.last3Days:
        return DateTime.now().subtract(const Duration(days: 3));
      case TimeRangeFilter.last7Days:
        return DateTime.now().subtract(const Duration(days: 7));
      case TimeRangeFilter.last30Days:
        return DateTime.now().subtract(const Duration(days: 30));
      case TimeRangeFilter.all:
        return DateTime(2000); // Effectively no time filter
    }
  }

  String _sanitizePath(String path) {
    return path.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  List<LogEntry> _applyFilters(List<LogEntry> logs) {
    return logs.where((log) {
      // Apply time range filter
      if (!log.timestamp.isAfter(_getTimeRangeCutoff())) {
        return false;
      }

      // Apply status filter
      switch (_selectedStatus) {
        case StatusFilter.success:
          if (log.error != null || log.statusCode >= 400) return false;
          break;
        case StatusFilter.error:
          if (log.error == null && log.statusCode < 400) return false;
          break;
        case StatusFilter.all:
          break;
      }

      // Apply search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return log.requestData.toString().toLowerCase().contains(query) ||
            log.responseData.toString().toLowerCase().contains(query) ||
            log.error?.toLowerCase().contains(query) == true;
      }

      return true;
    }).toList();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sanitizedPath = _sanitizePath(widget.endpointPath);
      final statsDoc = await _db.collection('endpoint_stats').doc(sanitizedPath).get();
      
      if (statsDoc != null) {
        final stats = RequestStats.fromJson(statsDoc);
        final filteredLogs = _applyFilters(stats.recentLogs)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        setState(() {
          _endpointStats = stats;
          _logs = filteredLogs;
        });
      } else {
        setState(() {
          _endpointStats = null;
          _logs = [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(widget.endpointPath),
        actions: [
          // Add filter button
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Show active filters chip if any filter is applied
          if (_selectedTimeRange != TimeRangeFilter.last7Days ||
              _selectedStatus != StatusFilter.all ||
              _searchQuery.isNotEmpty)
            _buildActiveFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    slivers: [
                      if (_endpointStats != null)
                        SliverToBoxAdapter(
                          child: _buildStatsCard(),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: _logs.isEmpty
                            ? SliverFillRemaining(
                                child: Center(
                                  child: Text('No logs found for the selected filters'),
                                ),
                              )
                            : SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _buildLogItem(_logs[index]),
                                  childCount: _logs.length,
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TimeRangeFilter>(
                    value: _selectedTimeRange,
                    decoration: const InputDecoration(
                      labelText: 'Time Range',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: TimeRangeFilter.values.map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedTimeRange = value;
                        });
                        _loadLogs();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<StatusFilter>(
                    value: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: StatusFilter.values.map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedStatus = value;
                        });
                        _loadLogs();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search',
                hintText: 'Search in request/response data',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                    _loadLogs();
                  },
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _loadLogs();
              },
            ),
          ],
        ),
      ),
    );
  }

   Widget _buildActiveFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_selectedTimeRange != TimeRangeFilter.last7Days)
            Chip(
              label: Text(_selectedTimeRange.label),
              onDeleted: () {
                setState(() {
                  _selectedTimeRange = TimeRangeFilter.last7Days;
                });
                _loadLogs();
              },
            ),
          if (_selectedStatus != StatusFilter.all)
            Chip(
              label: Text(_selectedStatus.label),
              onDeleted: () {
                setState(() {
                  _selectedStatus = StatusFilter.all;
                });
                _loadLogs();
              },
            ),
          if (_searchQuery.isNotEmpty)
            Chip(
              label: Text('Search: $_searchQuery'),
              onDeleted: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                });
                _loadLogs();
              },
            ),
        ],
      ),
    );
  }


  Widget _buildStatsCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ApiPerformanceGraph(
          stats: _endpointStats!,
          endpointPath: widget.endpointPath,
        ),
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Status: ${log.statusCode}',
              style: TextStyle(
                color: log.error != null || log.statusCode >= 400
                    ? Colors.red
                    : Colors.green,
              ),
            ),
            Text(
              '${log.responseTimeMs}ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(_formatTimestamp(log.timestamp)),
            if (log.error != null)
              Text(
                'Error: ${log.error}',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
        onTap: () => _showLogDetails(log),
      ),
    );
  }

  void _showLogDetails(LogEntry log) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Log Details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailSection('Request Data', log.requestData),
                      if (log.responseData != null)
                        _buildDetailSection('Response Data', log.responseData!),
                      _buildDetailSection('Headers', log.headers),
                      _buildDetailSection('Query Parameters', log.queryParameters),
                      const SizedBox(height: 8),
                      Text(
                        'Status Code: ${log.statusCode}',
                        style: TextStyle(
                          color: log.error != null || log.statusCode >= 400
                              ? Colors.red
                              : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text('Response Time: ${log.responseTimeMs}ms'),
                      Text('Timestamp: ${log.timestamp}'),
                      if (log.error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Error: ${log.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            data.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
        ),
        const SizedBox(height: 16),
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