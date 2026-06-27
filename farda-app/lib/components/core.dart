part of '_components.dart';

class ExtendedScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final bool resize;

  const ExtendedScaffold({super.key, this.appBar, required this.body, this.resize = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      extendBody: true,
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: resize,
      appBar: appBar,
      body: body,
    );
  }
}
