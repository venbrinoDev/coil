import 'package:coil/coil.dart';

final firstname = Coil((_) => 'First', debugName: 'firstname');
final lastname = MutableCoil((_) => 'Last', debugName: 'lastname');
final age = MutableCoil((_) => 0, debugName: 'age');

final passThrough = Coil.family((_, int value) => value, debugName: 'pass-through');
final mutablePassThrough = MutableCoil.family((_, int value) => value, debugName: 'mutable-pass-through');

final doubleAge = Coil((ref) => ref.get(age.state).value * 2, debugName: 'double-age');
final fullname = Coil((ref) => '${ref.get(firstname)} ${ref.get(lastname)}', debugName: 'fullname');
final result = Coil((ref) => '${ref.get(fullname)} (${ref.get(age)})', debugName: 'result');

final delayed = FutureCoil((_) => Future.delayed(Duration(seconds: 1), () => 1), debugName: 'delayed');
final unDelayed = FutureCoil((_) => 1, debugName: 'un-delayed');

final stream = StreamCoil((_) => Stream.value(1), debugName: 'stream');
final doubleStream = StreamCoil(
  (ref) async* {
    switch (ref.get(stream)) {
      case AsyncLoading<int>():
      case AsyncFailure<int>():
        break;
      case AsyncSuccess<int>(:final value):
        yield value * 2;
    }
  },
  debugName: 'double-stream',
);
final cubicStream = StreamCoil(
  (ref) async* {
    ref.listen(stream, (previous, next) {
      log('listen-inner-stream', (previous, next));
    });

    yield (await ref.get(stream.async)) * 3;
  },
  debugName: 'cubic-stream',
);

void main() async {
  final scope = Scope();

  /** Primitives **/
  log('result', scope.get(result));

  scope.listen(age, (previous, next) {
    log('listen-age', (previous, next));
  });

  scope.listen(doubleAge, (previous, next) {
    log('listen-double-age', (previous, next));
  });

  scope.listen(fullname, (previous, next) {
    log('listen-fullname', (previous, next));
  });

  scope.get(age.state).value++;

  log('result', scope.get(result));

  scope.invalidate(age);

  log('result', scope.get(result));

  scope.get(age.state).value += 2;

  log('result', scope.get(result));

  scope.get(lastname.state).update((value) => 'v. $value');

  log('fullname', scope.get(fullname));

  log('double-age', scope.get(doubleAge));

  log('result', scope.get(result));

  /** Families **/

  log('pass-through', scope.get(passThrough(1)));

  log('mutable-pass-through', scope.get(mutablePassThrough(1)));

  scope.get(mutablePassThrough(1).state).value++;

  log('mutable-pass-through', scope.get(mutablePassThrough(1)));

  /** Futures **/

  log('await-delayed', await scope.get(delayed.async));

  scope.listen(
    delayed,
    (previous, next) {
      log('listen-delayed', (previous, next));
    },
    fireImmediately: true,
  );

  log('un-delayed', scope.get(unDelayed));

  /** Streams **/

  scope.listen(stream, (previous, next) {
    log('listen-stream', (previous, next));
  });

  scope.listen(doubleStream, (previous, next) {
    log('listen-double-stream', (previous, next));
  });

  scope.listen(cubicStream, (previous, next) {
    log('listen-cubic-stream', (previous, next));
  });

  log('await-cubic-stream', await scope.get(cubicStream.async));

  scope.invalidate(stream);

  log('await-cubic-stream', await scope.get(cubicStream.async));

  scope.dispose();
}

void log<T>(String tag, T object) {
  print((tag, object).toString());
}
