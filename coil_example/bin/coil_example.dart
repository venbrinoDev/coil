import 'package:coil/coil.dart';

final Coil<String> firstname = Coil((_) => 'First', debugName: 'firstname');
final Coil<String> lastname = Coil((_) => 'Last', debugName: 'lastname');
final MutableCoil<int> age = MutableCoil((_) => 0, debugName: 'age');
final Coil<String> fullname = Coil((Ref ref) => '${ref.get(firstname)} ${ref.get(lastname)}', debugName: 'fullname');
final Coil<String> result = Coil((Ref ref) => '${ref.get(fullname)} (${ref.get(age)})', debugName: 'result');

void main() {
  final Scope scope = Scope();

  log(scope.get(age));
  log(scope.get(result));

  scope.listen(age, (int? previous, int next) {
    log(('age-listener', previous, next));
  });

  scope.mutate(age, (int value) => value + 1);

  log(scope.get(age.state).value);

  scope.get(age.state).value++;

  log(scope.get(age));
  log(scope.get(result));
}

void log<T>(T object) => print(object.toString());
