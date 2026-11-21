import 'package:flutter/foundation.dart';

/// Простая шина событий для уведомления галереи об изменениях.
class GalleryEvents {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyChanged() {
    revision.value++;
  }
}
