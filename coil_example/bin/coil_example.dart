import 'package:coil/coil.dart';

final firstname = coil((_) => 'First');
final lastname = coil((_) => 'Last');
final age = coil((_) => 0);
final fullname = coil((ref) => '${ref.use(firstname)} ${ref.use(lastname)}');
final result = coil((ref) => '${ref.use(fullname)} (${ref.use(age)})');

void main() {
  final scope = Scope();

  print(scope.use(result));
}
