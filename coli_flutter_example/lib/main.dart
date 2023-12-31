import 'dart:async';
import 'dart:math';

import 'package:coil/coil.dart';
import 'package:flutter/material.dart';

import 'coil_flutter.dart';

final firstname = Coil((_) => 'First');
final lastname = Coil((_) => 'Last');
final age = Coil((_) => 0);

final doubleAge = Coil((ref) => ref.get(age) * 2);
final result = Coil((ref) => '${ref.get(firstname)} ${ref.get(lastname)} (${ref.get(age)})');

final passThrough = Coil.family((_, int value) => value);

final counter = Coil((Ref<int> ref) {
  final timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
    final value = ref.mutateSelf((value) => (value ?? 0) + 1);

    if (value == 10) {
      ref.invalidateSelf();
    }
  });

  ref.onDispose(() {
    log('on-dispose-counter', 0);
    timer.cancel();
  });

  return 0;
});

// final delayed = Coil<AsyncSnapshot<int>>((ref) {
//   final value = ref.mutateSelf((value) {
//     if (value != null && value.hasData) {
//       return value.inState(ConnectionState.waiting);
//     }
//
//     return null;
//   });
//
//   Future.delayed(const Duration(seconds: 3)).then((value) {
//     ref.mutateSelf((value) {
//       return AsyncSnapshot<int>.withData(
//         ConnectionState.done,
//         Random().nextInt(100),
//       );
//     });
//   });
//
//   return value ?? const AsyncSnapshot<int>.waiting();
// });

final delayed = FutureCoil((ref) async {
  return Future.delayed(
    const Duration(seconds: 3),
    () => Random().nextInt(100),
  );
});

final class FutureCoil<T> extends Coil<AsyncSnapshot<T>> {
  FutureCoil(Future<T> Function(Ref<AsyncSnapshot<T>> ref) factory)
      : super((ref) {
          final value = ref.mutateSelf((value) {
            if (value != null && value.hasData) {
              return value.inState(ConnectionState.waiting);
            }

            return null;
          });

          factory(ref).then(
            (result) => ref.mutateSelf(
              (_) => AsyncSnapshot<T>.withData(
                ConnectionState.done,
                result,
              ),
            ),
          );

          return value ?? AsyncSnapshot<T>.waiting();
        });
}

void main() {
  runApp(const CoilScope(child: MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    context.listen(age, (previous, next) {
      log('listen-age', (previous, next));
    });

    log('rebuild', 'app');

    const spacing = SizedBox(height: 8);

    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Row(
              children: [
                Expanded(
                  child: CoilScope(
                    child: Builder(
                      builder: (context) => Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Age: ${context.get(age)}'),
                          spacing,
                          TextButton(
                            onPressed: () => context.mutate(age, (value) => value + 10),
                            child: const Text('mutate age += 10'),
                          ),
                          spacing,
                          TextButton(
                            onPressed: () => context.invalidate(age),
                            child: const Text('invalidate age'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('DoubleAge: ${context.get(doubleAge)}'),
                      spacing,
                      Text('Result: ${context.get(result)}'),
                      spacing,
                      Text('PassThrough: ${context.get(passThrough(1))}'),
                      spacing,
                      Builder(
                        builder: (context) => Text('Counter: ${context.get(counter)}'),
                      ),
                      spacing,
                      Builder(builder: (context) {
                        final state = context.get(delayed);
                        if (state.hasData && state.connectionState == ConnectionState.waiting) {
                          return Text('Delayed: Refreshing... (${state.requireData})');
                        } else if (state.hasData) {
                          return Text('Delayed: ${state.requireData}');
                        }

                        return const Text('Delayed: Loading..');
                      }),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => context.mutate(age, (value) => value + 1),
                      child: const Text('mutate age += 1'),
                    ),
                    spacing,
                    TextButton(
                      onPressed: () => context.mutate(lastname, (value) => 'v. $value'),
                      child: const Text('mutate lastname'),
                    ),
                    spacing,
                    TextButton(
                      onPressed: () => context
                        ..invalidate(age)
                        ..invalidate(lastname),
                      child: const Text('invalidate age + lastname'),
                    ),
                    spacing,
                    TextButton(
                      onPressed: () => context.mutate(passThrough(1), (value) => value + 1),
                      child: const Text('mutate passThrough += 1'),
                    ),
                    spacing,
                    TextButton(
                      onPressed: () => context.invalidate(passThrough(1)),
                      child: const Text('invalidate passThrough'),
                    ),
                    spacing,
                    TextButton(
                      onPressed: () => context.invalidate(counter),
                      child: const Text('invalidate counter'),
                    ),
                    spacing,
                    TextButton(
                      onPressed: () => context.invalidate(delayed),
                      child: const Text('invalidate delayed'),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void log<T>(String tag, T object) {
  debugPrint((tag, object).toString());
}
