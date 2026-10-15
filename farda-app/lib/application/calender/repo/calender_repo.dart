import 'package:farda/app_const/app_urls.dart';
import 'package:farda/utilities/api_service.dart';

/// Legacy presentation adapter. ConsumerRepository owns the new typed journey.
class CalenderRepo {
  Future<dynamic> getDoseTime() =>
      ApiService.getList(endpoint: AppUrls.getDoseTime, auth: true);
  Future<dynamic> getMood() =>
      ApiService.getList(endpoint: AppUrls.getMode, auth: true);
  Future<dynamic> setMood(String date, String emoji) => ApiService.post(
    endpoint: AppUrls.setMood,
    body: {'date': date, 'emoji': emoji},
    auth: true,
  );
  Future<int> submitNote(String id, String note) async {
    // Editing a note must never silently log a dose as taken.
    final response = await ApiService.patchResponse(
      endpoint: AppUrls.dose(id),
      body: {'note': note},
      auth: true,
    );
    return response?.statusCode ?? 0;
  }
}
