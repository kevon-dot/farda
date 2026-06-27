part of '_utilities.dart';

abstract class PresentationCubit<STATE, EVENT> extends Cubit<STATE>
    with BlocPresentationMixin<STATE, EVENT> {
  PresentationCubit(super.initialState);
}

class BlocPresentationProvider<B extends PresentationCubit<S, E>, S, E>
    extends StatelessWidget {
  final Widget child;
  final B Function(BuildContext context) create;
  final void Function(BuildContext context, E event)? onEvent;

  const BlocPresentationProvider({
    super.key,
    required this.create,
    required this.child,
    this.onEvent,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<B>(
      create: create,
      child: BlocPresentationListener<B, E>(
        listener: (context, event) => onEvent?.call(context, event),
        child: child,
      ),
    );
  }
}
