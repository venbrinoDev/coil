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
    final res = ref.get(stream);
    switch (res) {
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
    final value = await ref.get(stream.future);
    yield value * 3;
  },
  debugName: 'cubic-stream',
);

void main() async {
  final Scope scope = Scope();

  // log(scope.get(result));
  //
  // scope.listen(age, (previous, next) {
  //   log(('age-listener', previous, next));
  // });
  //
  // scope.mutate(age, (value) => value + 1);
  //
  // log(scope.get(result));
  //
  // scope.invalidate(age);
  //
  // log(scope.get(result));
  //
  // scope.get(age.state).value++;
  //
  // log(scope.get(result));
  //
  // scope.listen(delayed, (previous, next) {
  //   log(('delayed-listener', previous, next));
  // });
  //
  // log(scope.get(unDelayed));
  //
  scope.listen(stream, (previous, next) {
    log(('stream-listener', previous, next));
  });

  scope.listen(doubleStream, (previous, next) {
    log(('double-stream-listener', previous, next));
  });

  scope.listen(cubicStream, (previous, next) {
    log(('cubic-stream-listener', previous, next));
  });

  log(await scope.get(cubicStream.future));
}

void log<T>(T object) => print(object.toString());
