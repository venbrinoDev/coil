import 'package:coil/coil.dart';

final firstname = Coil((_) => 'First', debugName: 'firstname');
final lastname = Coil((_) => 'Last', debugName: 'lastname');
final age = MutableCoil((_) => 0, debugName: 'age');
final fullname = Coil((Ref ref) => '${ref.get(firstname)} ${ref.get(lastname)}', debugName: 'fullname');
final result = Coil((Ref ref) => '${ref.get(fullname)} (${ref.get(age)})', debugName: 'result');

final delayed = FutureCoil((_) => Future.delayed(Duration(seconds: 1), () => 1), debugName: 'delayed');
final unDelayed = FutureCoil((_) => 1, debugName: 'unDelayed');

void main() {
  final Scope scope = Scope();

  log(scope.get(result));

  scope.listen(age, (previous, next) {
    log(('age-listener', previous, next));
  });

  scope.mutate(age, (value) => value + 1);

  log(scope.get(result));

  scope.invalidate(age);

  log(scope.get(result));

  scope.get(age.state).value++;

  log(scope.get(result));

  scope.listen(delayed, (previous, next) {
    log(('delayed-listener', previous, next));
  });

  log(scope.get(unDelayed));
}

void log<T>(T object) => print(object.toString());
