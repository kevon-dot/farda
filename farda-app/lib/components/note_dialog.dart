import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void showThoughtsDialog(BuildContext context, CalenderProvider data) {
  TextEditingController notesController =
      TextEditingController(); // Controller for Notes TextField

  showDialog(
    context: context,
    builder:
        (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Row with Close
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sticky_note_2_outlined, color: Colors.grey),
                        SizedBox(width: 8),
                        Text(
                          "Thoughts?",
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                // Notes placeholder with TextField
                // Align(
                //   alignment: Alignment.centerLeft,
                //   child: Text(
                //     "Notes",
                //     style: TextStyle(color: Colors.grey),
                //   ),
                // ),
                // SizedBox(height: 8),
                TextField(
                  controller:
                      notesController, // Connect the controller to the TextField
                  maxLines: 5, // Set a maximum number of lines
                  decoration: InputDecoration(
                    hintText: 'Notes',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.all(8),
                  ),
                ),
                SizedBox(height: 20),

                // Icons row
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.sticky_note_2_outlined, color: Colors.grey),
                    SizedBox(width: 5),
                    Icon(Icons.label_outline, color: Colors.grey),
                    SizedBox(width: 5),
                    Icon(Icons.list_outlined, color: Colors.grey),
                    SizedBox(width: 5),
                    Icon(Icons.flag_outlined, color: Colors.grey),
                  ],
                ),
                SizedBox(height: 20),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      // Logic for saving the notes can be placed here
                      String notes =
                          notesController.text; // Get the entered notes
                      print(
                        'Saved Notes: ${data.selectedDoseModel.id.toString()},',
                      );

                      String status = await data.setNotesApi(
                        data.selectedDoseModel.id.toString(),
                        notes,
                      );

                      Navigator.of(context).pop();
                      CustomSnackbar.show(context, message: status);
                      context.pop();
                    },
                    child: Text("Save", style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
  );
}
