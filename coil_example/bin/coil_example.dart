import 'dart:async';

import 'package:coil/coil.dart';

final firstname = Coil((_) => 'First', debugName: 'firstname');
final lastname = Coil((_) => 'Last', debugName: 'lastname');
final age = Coil((_) => 0, debugName: 'age');

final doubleAge = Coil((ref) => ref.get(age) * 2, debugName: 'double-age');
final result = Coil((ref) => '${ref.get(firstname)} ${ref.get(lastname)} (${ref.get(age)})', debugName: 'result');

final passThrough = Coil.family((_, int value) => value, debugName: 'pass-through');

final counter = Coil((Ref<int> ref) {
  final timer = Timer.periodic(Duration(milliseconds: 100), (_) {
    ref.mutateSelf((value) => (value ?? 0) + 1);

    // if (value == 10) {
    //   _.cancel();
    // }
  });

  ref.onDispose(() {
    timer.cancel();
  });

  return 0;
}, debugName: 'timer');

void main() async {
  final scope = Scope();

  scope.onDispose(() {
    log('on-dispose-scope', 0);
  });

  /** Primitives **/

  log('result', scope.get(result));

  scope.listen(age, (previous, next) {
    log('listen-age', (previous, next));
  });

  scope.listen(doubleAge, (previous, next) {
    log('listen-double-age', (previous, next));
  });

  scope.mutate(age, (value) => value + 1);

  log('result', scope.get(result));

  scope.invalidate(age);

  log('result', scope.get(result));

  scope.mutate(age, (value) => value + 2);

  log('result', scope.get(result));

  scope.mutate(lastname, (value) => 'v. $value');

  log('double-age', scope.get(doubleAge));

  log('result', scope.get(result));

  /** End Primitives **/

  /** Families **/

  log('pass-through', scope.get(passThrough(1)));

  scope.mutate(passThrough(1), (value) => value + 1);

  log('pass-through', scope.get(passThrough(1)));

  /** End Families **/

  /** Self Mutation **/

  scope.listen(counter, (previous, next) {
    log('listen-counter', (previous, next));
  });

  /** End Self Mutation **/

  Timer(Duration(seconds: 3), () => scope.dispose());
}

void log<T>(String tag, T object) {
  print((tag, object).toString());
}
