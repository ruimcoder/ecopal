import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/cloud_consent_dialog.dart';

/// Manages user consent for sending camera frames to the cloud API.
///
/// Consent is sticky once granted — the user is never asked again.
/// "Not now" denies for the current session only (not persisted).
class ConsentService {
  ConsentService(this._prefs);

  static const _kConsentKey = 'cloud_fallback_consent_granted';

  final SharedPreferences _prefs;

  /// Returns `true` if the user has previously granted cloud fallback consent.
  Future<bool> hasCloudFallbackConsent() async {
    return _prefs.getBool(_kConsentKey) ?? false;
  }

  /// Persists the user's consent decision.
  ///
  /// Once set to `true` the consent is sticky and [requestConsentIfNeeded]
  /// will not show a dialog again.
  Future<void> setCloudFallbackConsent({required bool granted}) async {
    await _prefs.setBool(_kConsentKey, granted);
  }

  /// Shows a consent dialog if the user has not yet granted consent.
  ///
  /// Returns `true` if consent is (or was already) granted.
  /// "Not now" returns `false` without persisting, so the dialog is shown
  /// again on the next cold start.
  Future<bool> requestConsentIfNeeded(BuildContext context) async {
    if (await hasCloudFallbackConsent()) {
      return true;
    }

    if (!context.mounted) return false;

    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CloudConsentDialog(),
    );

    final userGranted = granted ?? false;
    if (userGranted) {
      await setCloudFallbackConsent(granted: true);
    }
    // "Not now" (false) is intentionally NOT persisted so we ask again next
    // cold start.
    return userGranted;
  }
}
