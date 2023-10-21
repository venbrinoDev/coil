import 'package:coil/coil.dart';

final Coil<String> firstname = Coil((_) => 'First', debugName: 'firstname');
final Coil<String> lastname = Coil((_) => 'Last', debugName: 'lastname');
final MutableCoil<int> age = MutableCoil((_) => 0, debugName: 'age');
final Coil<String> fullname = Coil((Ref ref) => '${ref.get(firstname)} ${ref.get(lastname)}', debugName: 'fullname');
final Coil<String> result = Coil((Ref ref) => '${ref.get(fullname)} (${ref.get(age)})', debugName: 'result');

void main() {
  final Scope scope = Scope();

  print(scope.get(age).value);
  print(scope.get(result));

  scope.listen(age, (int? previous, int next) {
    print((previous, next));
  });

  scope.get(age).value++;
  scope.get(age).value++;

  print(scope.get(age).value);
  print(scope.get(result));
}
