part of '_utilities.dart';


extension MapIndexExtension<T> on Iterable<T> {
  Iterable<R> mapIndex<R>(R Function(int index, T element) f) sync* {
    int idx = 0;
    for (final element in this) {
      yield f(idx, element);
      idx++;
    }
  }
}