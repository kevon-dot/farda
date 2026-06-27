part of './_components.dart';

// The "Thoughts?" note dialog previously lived here as `ThoughtDialog`, but it
// was a non-functional duplicate (a TextField with no controller and a no-op
// Save button). It has been consolidated into `showThoughtsDialog` in
// `note_dialog.dart`, which actually persists the note via `CalenderProvider`.
