import 'package:flutter/widgets.dart';

import '../../app_state.dart';
import '../../data/tracker_service.dart';

/// Builds with the app's [TrackerService] (null until it has opened) and
/// rebuilds whenever it changes. Opening is triggered on first build.
class TrackerBuilder extends StatefulWidget {
  const TrackerBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, TrackerService? tracker) builder;

  @override
  State<TrackerBuilder> createState() => _TrackerBuilderState();
}

class _TrackerBuilderState extends State<TrackerBuilder> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (state.trackerService == null) state.tracker().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppScope.of(context).trackerService;
    if (svc == null) return widget.builder(context, null);
    return ListenableBuilder(listenable: svc, builder: (context, _) => widget.builder(context, svc));
  }
}
