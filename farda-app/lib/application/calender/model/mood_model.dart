class MoodModel {
  String? date;
  String? emoji;
  int? user;

  MoodModel({this.date, this.emoji, this.user});

  MoodModel.fromJson(Map<String, dynamic> json) {
    date = json['date'];
    emoji = json['emoji'];
    user = json['user'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['date'] = this.date;
    data['emoji'] = this.emoji;
    data['user'] = this.user;
    return data;
  }
}
