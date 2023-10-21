import 'package:coil/coil.dart';

final firstname = Coil((_) => 'First', debugName: 'firstname');
final lastname = Coil((_) => 'Last', debugName: 'lastname');
final age = MutableCoil((_) => 0, debugName: 'age');
final fullname = Coil((Ref ref) => '${ref.get(firstname)} ${ref.get(lastname)}', debugName: 'fullname');
final result = Coil((Ref ref) => '${ref.get(fullname)} (${ref.get(age)})', debugName: 'result');

void main() {
  final Scope scope = Scope();

  log(scope.get(result));

  scope.listen(age, (int? previous, int next) {
    log(('age-listener', previous, next));
  });

  scope.mutate(age, (int value) => value + 1);

  log(scope.get(result));

  scope.invalidate(age);

  log(scope.get(result));

  scope.get(age.state).value++;

  log(scope.get(result));

  scope.dispose();
}

void log<T>(T object) => print(object.toString());
