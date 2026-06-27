// import 'package:farda/components/_components.dart';
// import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:provider/provider.dart';

// class ScreenCalendar extends StatefulWidget {
//   const ScreenCalendar({super.key});

//   @override
//   State<ScreenCalendar> createState() => _ScreenCalendarState();
// }

// class _ScreenCalendarState extends State<ScreenCalendar> {
//   final calendarController = CalendarController();

//   // @override
//   // void initState() {
//   //   super.initState();
//   //   Future.delayed(Duration(seconds: 2), () {
//   //     calendarController.setEvents({
//   //       DateFormat('yyyy-MM-dd').format(DateTime.now()): [
//   //         CalendarEvent(
//   //           'Morning Dose',
//   //           TimeOfDay(hour: 9, minute: 0),
//   //           TimeOfDay(hour: 9, minute: 36),
//   //           Colors.green,
//   //         ),
//   //         CalendarEvent(
//   //           'Early Afternoon Dose',
//   //           TimeOfDay(hour: 14, minute: 30),
//   //           TimeOfDay(hour: 15, minute: 0),
//   //           Colors.orange,
//   //         ),
//   //         CalendarEvent(
//   //           'Evening Dose',
//   //           TimeOfDay(hour: 18, minute: 0),
//   //           TimeOfDay(hour: 19, minute: 15),
//   //           Colors.red,
//   //         ),
//   //         CalendarEvent(
//   //           'Mid Night Dose',
//   //           TimeOfDay(hour: 23, minute: 0),
//   //           TimeOfDay(hour: 23, minute: 10),
//   //           Colors.yellow,
//   //         ),
//   //       ],
//   //     });
//   //   });
//   // }

//   @override
//   Widget build(BuildContext context) {
//     final provider = context.watch<CalenderProvider>();

//     calendarController.setEvents({
//       DateFormat('yyyy-MM-dd').format(DateTime.now()):

//       // List.generate(
//       //   provider.doseTimeModel.length,
//       //   (index) {
//       //     return CalendarEvent(
//       //       provider.doseTimeModel[index].name.toString(),
//       //       TimeOfDay(
//       //         hour: int.parse(
//       //           provider.doseTimeModel[index].startTime!.split(":")[0],
//       //         ),
//       //         minute: int.parse(
//       //           provider.doseTimeModel[index].startTime!.split(":")[1],
//       //         ),
//       //       ),
//       //       TimeOfDay(
//       //         hour: int.parse(
//       //           provider.doseTimeModel[index].endTime!.split(":")[0],
//       //         ),
//       //         minute: int.parse(
//       //           provider.doseTimeModel[index].endTime!.split(":")[1],
//       //         ),
//       //       ),
//       //       Colors.green,
//       //     );
//       //   },
//       // ),

//       [

//         CalendarEvent(
//           'Early Afternoon Dose',
//           TimeOfDay(hour: 14, minute: 30),
//           TimeOfDay(hour: 15, minute: 0),
//           Colors.orange,
//         ),
//         CalendarEvent(
//           'Evening Dose',
//           TimeOfDay(hour: 18, minute: 0),
//           TimeOfDay(hour: 19, minute: 15),
//           Colors.red,
//         ),
//         CalendarEvent(
//           'Mid Night Dose',
//           TimeOfDay(hour: 23, minute: 0),
//           TimeOfDay(hour: 23, minute: 10),
//           Colors.yellow,
//         ),
//       ],
//     });

//     return Scaffold(
//       body: SafeArea(child: CustomCalendarView(controller: calendarController)),
//     );
//   }
// }
//  Map<String, dynamic>? dose = doses.where(
//   (d) => d['time'].hour == time.hour,
// ).cast<Map<String, dynamic>?>().firstOrNull;

import 'package:farda/application/calender/model/dose_time_model.dart';
import 'package:farda/components/note_dialog.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/emoji/screen_emoji.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

 // Assuming the provider is in calender_provider.dart
// Assuming DoseTimeModel is in dose_time_model.dart

class ScreenCalendar extends StatefulWidget {
  const ScreenCalendar({super.key});

  @override
  State<ScreenCalendar> createState() => _ScreenCalendarState();
}

class _ScreenCalendarState extends State<ScreenCalendar> {
  int selectedIndex = 0;
  DateTime currentMonth = DateTime.now();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    if (today.year == currentMonth.year && today.month == currentMonth.month) {
      selectedIndex = today.day - 1;
      // Scroll after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelectedIndex();
      });
    }
    // Fetch data
    // Provider.of<CalenderProvider>(context, listen: false).getDoseTimeApi();
  }

  void _scrollToSelectedIndex() {
    double offset = (selectedIndex * 72.0).clamp(
      0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  List<DateTime> get fullMonthDates {
    int totalDays = DateTime(currentMonth.year, currentMonth.month + 1, 0).day;
    return List.generate(
      totalDays,
      (index) => DateTime(currentMonth.year, currentMonth.month, index + 1),
    );
  }

  // Reusable DoseCard Widget
  Widget buildDoseCard(DoseTimeModel dose, String time) {
    // final startTime = DateFormat('HH:mm:ss').parse(dose.first.startTime!);
    // final endTime = DateFormat('HH:mm:ss').parse(dose.first.endTime!);
    // final duration = endTime.difference(startTime).inMinutes;

    // final height = (duration / 140) * 100.0; // Proportional height based on 24 hours

    return  Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          // height: height, // Set dynamic height based on time difference
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dose.name!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    context.watch<CalenderProvider>().getModelEmoji(), // Name as emoji placeholder
                    style: const TextStyle(fontSize: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(time),
              SizedBox(height: 50),

              // Time display
            ],
          ),
        );
  }

  // Reusable EmptyDoseCard Widget
  Widget buildEmptyDoseCard() {
    return  Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dose title and emoji placeholder
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "", // You can replace this with dynamic text if necessary
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "", // Emoji or placeholder
                    style: const TextStyle(fontSize: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(""), // Additional time or information display can go here
              const SizedBox(height: 50),
            ],
          ),
        );
  }

  // Reusable HourRow Widget
  Widget buildHourRow(TimeOfDay time, CalenderProvider data) {
  List<DoseTimeModel> doseList =data.doseTimeModel;

  // Convert the TimeOfDay to 24-hour format string (HH:mm:ss)
  String timeFormatted = DateFormat('HH:mm:ss').format(
    DateTime(0, 1, 1, time.hour, time.minute), // Convert TimeOfDay to DateTime
  );

  // Find the index of the dose whose startTime matches the formatted time
  int index = doseList.indexWhere((e) {
    // Compare 24-hour time format of startTime and formatted time
    return e.startTime == timeFormatted;
  });

  TimeOfDay currentTime = TimeOfDay.now(); // Get the current time as TimeOfDay
 // Convert TimeOfDay to DateTime to use DateFormat
    DateTime now = DateTime(0, 1, 1, currentTime.hour, currentTime.minute);

    // Format DateTime to 12-hour format (hh:mm a)
    String formattedTime = DateFormat('hh:mm a').format(now);
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            // Display the hour text in 12-hour format
            Text(time.format(context), style: const TextStyle(fontSize: 12)),

            // Vertical divider
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Container(
                width: 0.5,
                color: Color(0xFFE0E0E0),
                height: 130, // Height of the vertical divider
              ),
            ),

            // If current time hour matches the time hour, display extra dividers and current time
            currentTime.hour == time.hour &&  doseList.isNotEmpty && index != -1 
                ?  SizedBox.shrink( ) : 
               currentTime.hour == time.hour  ?
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        Container(
                          color: Colors.black,
                          height: 0.3,
                          width: 100, // Divider width on the left side of the current time
                        ),
                        SizedBox(width: 5,),
                        Text(formattedTime.toString()), 
                        SizedBox(width: 5,),// Display the current hour
                        Container(
                          color: Colors.black,
                          height: 0.3,
                          width: 100// Divider width on the right side of the current time
                        ),
                      ],
                    ),
                  ),
                )
                : const SizedBox(), // Empty space when time doesn't match

            // Dose Card or Empty Dose Card
            Expanded(
              child:    currentTime.hour == time.hour &&  doseList.isNotEmpty && index != -1  ?  Column(
                children: [
                  InkWell(
                        onTap: (){
                      
                        },
                        child: buildDoseCard(doseList[index], time.format(context))),

                        Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        Container(
                          color: Colors.black,
                          height: 0.3,
                          width: 100, // Divider width on the left side of the current time
                        ),
                        SizedBox(width: 5,),
                        Text(formattedTime.toString()), 
                        SizedBox(width: 5,),// Display the current hour
                        Container(
                          color: Colors.black,
                          height: 0.3,
                          width: 100// Divider width on the right side of the current time
                        ),
                      ],
                    ),
                  ),
                ],
              ) : doseList.isNotEmpty && index != -1 // Check if the list is not empty and index is valid
                  ? InkWell(
                    onTap: (){
                      print("data tap");
                      
                      //  showThoughtsDialog(context);
                     
                      data.selectDoes(doseList[index]);
                 

                      context.go(CustomRoutePaths.emoji);
                     
                    //  Navigator.push(context, MaterialPageRoute(builder: (_)=> ScreenEmoji())); 

                    },
                    child: buildDoseCard(doseList[index], time.format(context))) // Display DoseCard
                  :    buildEmptyDoseCard(), // Fallback for empty dose
            ),
          ],
        ),
      ),
      const Divider(height: 1, color: Color(0xFFE0E0E0),), // Divider at the end of the row
    ],
  );
}


  // Month Navigation Widget
  void changeMonth(bool forward) {
    setState(() {
      currentMonth = DateTime(
        currentMonth.year,
        currentMonth.month + (forward ? 1 : -1),
        1,
      );
      selectedIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedIndex();
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeSlots = List.generate(
      20,
      (i) => TimeOfDay(hour: 5 + i, minute: 0),
    );
    final data = context.watch<CalenderProvider>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Month Navigation Widget
            MonthNavigationWidget(
              changeMonth: changeMonth,
              currentMonth: currentMonth,
            ),
            // Scrollable Dates Row
            SizedBox(
              height: 70,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: fullMonthDates.length,
                itemBuilder: (context, index) {
                  final date = fullMonthDates[index];
                  final isSelected = selectedIndex == index;
                  return DateCellWidget(
                    date: date,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() => selectedIndex = index);
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE0E0E0),),
            // Time-based dose list
            Expanded(
              child: ListView.builder(
                itemCount: timeSlots.length,
                itemBuilder: (context, index) => buildHourRow(timeSlots[index], data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Month Navigation Widget
class MonthNavigationWidget extends StatelessWidget {
  final void Function(bool forward) changeMonth;
  final DateTime currentMonth;

  const MonthNavigationWidget({
    required this.changeMonth,
    required this.currentMonth,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => changeMonth(false),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            DateFormat('MMMM yyyy').format(currentMonth),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            onPressed: () => changeMonth(true),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

// DateCellWidget - Cell for each date in the month view
class DateCellWidget extends StatelessWidget {
  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;

  const DateCellWidget({
    required this.date,
    required this.isSelected,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat.E().format(date),
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                ),
                const SizedBox(height: 4),
                isSelected
                    ? DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xff2D9CDB),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text(
                          date.day.toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                    : Text(
                      date.day.toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontSize: 12,
                      ),
                    ),
              ],
            ),
            SizedBox(width: 5,),
            Container(
              width: 0.2,
              color: Color(0xFFE0E0E0),
            )
          ],
        ),
      ),
    );
  }
}




class StraightContainerWithCircles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Container with Circles'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Left Circle
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.blue, // Color of the left circle
                  shape: BoxShape.circle,
                ),
              ),

              // Straight Container (Expanded to take available space)
              Container(
                height: 0.5, 
                width: 100,// Height of the straight container
                color: Colors.black, // Color of the container
              ),

              // Right Circle
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.red, // Color of the right circle
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  runApp(MaterialApp(
    home: StraightContainerWithCircles(),
  ));
}
