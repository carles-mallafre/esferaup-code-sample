/// Outcome of saving a UP / Crisi (the 201 body — lets the Guardat screen
/// celebrate without a second round-trip).
class UpSaveResult {
  const UpSaveResult({
    required this.id,
    required this.puntsAwarded,
    required this.dailyCapReached,
  });

  final String id;
  final int puntsAwarded;
  final bool dailyCapReached;
}
