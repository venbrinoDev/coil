import 'package:coil/coil.dart';

final firstname = Coil((_) => 'First', debugName: 'firstname');
final lastname = Coil((_) => 'Last', debugName: 'lastname');
final age = MutableCoil((_) => 0, debugName: 'age');
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
    yield (await ref.get(stream.future)) * 3;
  },
  debugName: 'cubic-stream',
);

void main() async {
  final Scope scope = Scope();

  log('result', scope.get(result));

  scope.listen(age, (previous, next) {
    log('listen-age', (previous, next));
  });

  scope.mutate(age, (value) => value + 1);

  log('result', scope.get(result));

  scope.invalidate(age);

  log('result', scope.get(result));

  scope.get(age.state).value++;

  log('result', scope.get(result));

  log('await-delayed', await scope.get(delayed.future));

  scope.listen(delayed, (previous, next) {
    log('listen-delayed', (previous, next));
  });

  log('un-delayed', scope.get(unDelayed));

  scope.listen(stream, (previous, next) {
    log('listen-stream', (previous, next));
  });

  scope.listen(doubleStream, (previous, next) {
    log('listen-double-stream', (previous, next));
  });

  scope.listen(cubicStream, (previous, next) {
    log('listen-cubic-stream', (previous, next));
  });

  log('await-cubic-stream', await scope.get(cubicStream.future));
}

void log<T>(String tag, T object) => print((tag, object).toString());
