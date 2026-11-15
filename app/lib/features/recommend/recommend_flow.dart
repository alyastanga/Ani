import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/planner.dart';
import '../../data/planner_profile.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import 'questionnaire_screen.dart';
import 'result_screen.dart';

export 'answers.dart' show RecommendAnswers;
export 'questionnaire_screen.dart' show QuestionnaireScreen;
export 'result_screen.dart' show CropCardView, HoldView, ResultScreen;

/// Opens the recommendation questionnaire (Home CTA "What should I plant?").
/// It is prefilled with the saved answers, or the app's town; finishing it
/// saves the answers ([AppState.savePlannerProfile]) and shows the result.
Future<void> openRecommendFlow(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QuestionnaireScreen()));

/// Reopens the last recommendation from the saved answers, re-planned on the
/// town's bundle ([AppState.lastRecommendation]). Falls back to the
/// questionnaire when nothing is saved.
Future<void> openLastRecommendation(BuildContext context) {
  if (!AppScope.of(context).hasRecommendation) return openRecommendFlow(context);
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SavedResultScreen()));
}

/// Loads [AppState.lastRecommendation] and shows it in a [ResultScreen].
class SavedResultScreen extends StatefulWidget {
  const SavedResultScreen({super.key});

  @override
  State<SavedResultScreen> createState() => _SavedResultScreenState();
}

class _SavedResultScreenState extends State<SavedResultScreen> {
  Future<({SavedPlannerProfile saved, PlanResult result})?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).lastRecommendation();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        final r = snap.data;
        if (r != null) return ResultScreen(saved: r.saved, result: r.result);
        final l = AppLocalizations.of(context);
        final done = snap.connectionState == ConnectionState.done;
        return Scaffold(
          backgroundColor: AniColors.cream,
          appBar: AppBar(backgroundColor: AniColors.cream, elevation: 0),
          body: Center(
            child: done
                ? Text(snap.hasError ? l.bundleLoadError : l.recommendNoSaved)
                : const CircularProgressIndicator(color: AniColors.olive),
          ),
        );
      },
    );
  }
}
