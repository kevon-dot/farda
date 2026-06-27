class DoseTimeModel {
  int? id;
  String? name;
  String? startTime;
  String? endTime;
  int? user;

  DoseTimeModel({this.id, this.name, this.startTime, this.endTime, this.user});

  DoseTimeModel.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    startTime = json['start_time'];
    endTime = json['end_time'];
    user = json['user'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['id'] = this.id;
    data['name'] = this.name;
    data['start_time'] = this.startTime;
    data['end_time'] = this.endTime;
    data['user'] = this.user;
    return data;
  }
}
