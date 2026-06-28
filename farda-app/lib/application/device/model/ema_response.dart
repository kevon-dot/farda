/// GTM-521 — EMA (ecological momentary assessment) self-report.
///
/// After a dose-event sync, on a server-decided SUB-SAMPLE, the app asks "Did you
/// just take your dose?" (yes / no / unsure). The answer is the SUPERVISED LABEL
/// the Vial backend validates device dose-detection against
/// (smart-vial-backend `utils/groundTruthMetrics.js`), so we keep it PHI-free:
/// one constrained enum value + the opaque `dose_event_id` it followed.
///
/// This model is pure (no widgets / network) so the answer mapping and the wire
/// body shape are unit-testable under `flutter test` in CI.
enum EmaAnswer {
  /// "Yes, I took it" ⇒ ground-truth label `taken`.
  taken,

  /// "No, I didn't" ⇒ ground-truth label `not_taken`.
  notTaken,

  /// "Not sure" ⇒ a real answer, but NOT usable ground truth (the backend counts
  /// it separately, never guessing a label).
  unsure,
}

extension EmaAnswerWire on EmaAnswer {
  /// The exact string the Vial `recordEmaResponse` endpoint expects for
  /// `self_reported_taken` (matches `GROUND_TRUTH` in groundTruthMetrics.js).
  String get wireValue {
    switch (this) {
      case EmaAnswer.taken:
        return 'taken';
      case EmaAnswer.notTaken:
        return 'not_taken';
      case EmaAnswer.unsure:
        return 'unsure';
    }
  }
}

/// One EMA self-report ready to POST to the Vial backend.
class EmaResponse {
  /// The vial this self-report concerns (path-bound on the backend too; sent so
  /// the body is self-describing).
  final String deviceId;

  /// The patient's answer to the prompt.
  final EmaAnswer answer;

  /// The detected dose event this prompt followed, if known (server-issued in the
  /// dose-event ingest response's `ema_prompt.dose_event_id`). Lets the backend
  /// pair this label to that exact detection.
  final String? doseEventId;

  const EmaResponse({
    required this.deviceId,
    required this.answer,
    this.doseEventId,
  });

  /// Stable idempotency key so a retried submission de-dupes to one row on the
  /// backend. Derived from the device + the dose it answers (NOT wall-clock), so
  /// re-sending the same answer for the same dose can't double-count.
  String get idempotencyKey =>
      'ema_${deviceId}_${doseEventId ?? 'na'}_${answer.wireValue}';

  /// The exact JSON body the Vial `recordEmaResponse` endpoint expects. Extracted
  /// so the payload shape is unit-testable without any network.
  Map<String, dynamic> toBody() {
    return {
      'self_reported_taken': answer.wireValue,
      if (doseEventId != null) 'dose_event_id': doseEventId,
      'idempotency_key': idempotencyKey,
    };
  }
}
