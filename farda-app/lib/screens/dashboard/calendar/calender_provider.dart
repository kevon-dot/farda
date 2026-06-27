import 'dart:convert';
import 'package:farda/application/calender/model/dose_time_model.dart';
import 'package:farda/application/calender/model/mood_model.dart';
import 'package:farda/application/calender/repo/calender_repo.dart';
import 'package:farda/application/emoji/emoji_model.dart';
import 'package:farda/components/_components.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalenderProvider extends ChangeNotifier {
  List<DoseTimeModel> doseTimeModel = [];
  MoodModel moodModel = MoodModel();
  DoseTimeModel selectedDoseModel = DoseTimeModel();

  Future<void> getDoseTimeApi() async {
    try {
      final response = await CalenderRepo().getDoseTime();

      if (response != null && response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        if (data.isNotEmpty) {
          doseTimeModel =
              data.map((item) => DoseTimeModel.fromJson(item)).toList();
          notifyListeners();
          debugPrint(doseTimeModel.toString());
        }
      }
    } catch (e) {
      debugPrint("getDoseTimeApi error: $e");
    }
  }

  Future<void> getMoodApi() async {
    try {
      final response = await CalenderRepo().getMood();

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data.isNotEmpty) {
          moodModel = MoodModel.fromJson(data);
          
          notifyListeners();
          debugPrint(doseTimeModel.toString());
        }
      }
    } catch (e) {
      debugPrint("getDoseTimeApi error: $e");
    }
  }

  getCallAllApi() {
    getDoseTimeApi();
    getMoodApi();
  }


void selectDoes(DoseTimeModel model){
  selectedDoseModel = DoseTimeModel();
  selectedDoseModel = model;
  print(selectedDoseModel.id);
  notifyListeners();
}

Future<String> setMoodApi(String emoji)async{
  SharedPreferences preferences = await SharedPreferences.getInstance();
    final data = await CalenderRepo().setMood(getCurrentDate(), emoji);
    if(data['message'] == "Mood created"){
      moodModel = MoodModel(
        date: data["date"],
        emoji: data["emoji"],
        user: int.parse(preferences.getString("id").toString())
      );
      notifyListeners();
      return "Mood Crated Successfully";
    }else if(data["message"] == "Mood updated"){
       moodModel = MoodModel(
        date: data["date"],
        emoji: data["emoji"],
        user: int.parse(preferences.getString("id").toString())
      );
      notifyListeners();
      return "Mood Updated Sucessfully";
    }else{
      return "Something worng, try again";
    }
}


Future<String> setNotesApi(String id, String notes)async{
    final data = await CalenderRepo().submitNote(id, notes);
    if(data == 201){
      return "Note Crated Successfully";
    }else{
      return "Something worng, try again";
    }
}

 String getModelEmoji() {
  // Check if moodModel is null
  if (moodModel == MoodModel()) {
    return ''; // Return empty string if moodModel is null
  }

  // Safely try to find the emoji in emojiList
  try {
    var emoji = emojiList.firstWhere(
      (e) => e.name == moodModel!.emoji, 
     // Return null if no match is found
    );

    // If emoji is found, return the emoji, otherwise return an empty string
    return emoji?.emoji ?? ''; // Return emoji or empty string if emoji is null
  } catch (e) {
    return ''; // If an error occurs (e.g., no matching emoji), return an empty string
  }
}




  List<Feeling> emojiList = [
    Feeling(emoji: '😟', name: 'Worried'),
    Feeling(emoji: '😀', name: 'Happy'),
    Feeling(emoji: '😁', name: 'Excited'),
    Feeling(emoji: '🥹', name: 'Emotional'),
    Feeling(emoji: '😂', name: 'Laughing'),
    Feeling(emoji: '🥲', name: 'Grateful'),
    Feeling(emoji: '☺️', name: 'Content'),
    Feeling(emoji: '😇', name: 'Innocent'),
    Feeling(emoji: '😊', name: 'Joyful'),
    Feeling(emoji: '😍', name: 'In Love'),
    Feeling(emoji: '🥰', name: 'Affectionate'),
    Feeling(emoji: '😞', name: 'Disappointed'),
    Feeling(emoji: '😏', name: 'Smug'),
    Feeling(emoji: '🥺', name: 'Pleading'),
    Feeling(emoji: '😠', name: 'Angry'),
    Feeling(emoji: '🧐', name: 'Curious'),
    Feeling(emoji: '🤔', name: 'Thinking'),
    Feeling(emoji: '🤭', name: 'Embarrassed'),
    Feeling(emoji: '🫣', name: 'Shy'),
    Feeling(emoji: '🥱', name: 'Tired'),
    // Add more as needed
  ];
}
