import 'package:coil/coil.dart';

final firstname = coil((_) => 'First', debugName: 'firstname');
final lastname = coil((_) => 'Last', debugName: 'lastname');
final age = mutableCoil((_) => 0, debugName: 'age');
final fullname = coil((ref) => '${ref.use(firstname)} ${ref.use(lastname)}', debugName: 'fullname');
final result = coil((ref) => '${ref.use(fullname)} (${ref.use(age)})', debugName: 'result');

void main() {
  final scope = Scope();

  print(scope.use<int>(age));
  print(scope.use(result));

  scope.mutate(age, (age) => age + 1);

  print(scope.use<int>(age));
  print(scope.use(result));
}
