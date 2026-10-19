import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Bottom inset for bottom-sheet content: the keyboard when it is up, otherwise
/// the home-indicator area. `showModalBottomSheet(useSafeArea: true)` only
/// protects the top edge, so sheets add this to their bottom padding.
double sheetBottomInset(BuildContext context) => math.max(
  MediaQuery.viewInsetsOf(context).bottom,
  MediaQuery.viewPaddingOf(context).bottom,
);
