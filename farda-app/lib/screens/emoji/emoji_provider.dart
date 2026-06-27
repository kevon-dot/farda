import 'package:farda/application/emoji/emoji_model.dart';
import 'package:flutter/material.dart';

class EmojiProvider extends ChangeNotifier {
  List<Feeling> feelings = [
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
  int selected = 0;
  String selectedName = "";

  selecteEmoji(int index, String name) {
    selected = index;
    selectedName = name;
    notifyListeners();
  }

int getEmojiIndex(String emojiName) {
  try {
    // Use firstWhere to find the emoji matching the emojiName
    return feelings.indexWhere((e) => e.name == emojiName);
  } catch (e) {
    // Return -1 or handle the error if no match is found
    return -1;
  }
}


}
