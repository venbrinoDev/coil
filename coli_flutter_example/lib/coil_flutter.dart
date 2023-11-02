import 'dart:async';

import 'package:coil/coil.dart';
import 'package:flutter/widgets.dart';

class CoilScope extends StatefulWidget {
  const CoilScope({super.key, required this.child});

  final Widget child;

  static _CoilScopeState _of(BuildContext context) {
    final _CoilScopeMarker? result = context.getInheritedWidgetOfExactType<_CoilScopeMarker>();
    assert(result != null, 'No CoilRootScope found in context');
    return result!.state;
  }

  @override
  State<CoilScope> createState() => _CoilScopeState();
}

class _CoilScopeState extends State<CoilScope> {
  final Scope _scope = Scope();
  final Map<BuildContext, Set<CoilSubscription>> _listeners = {};

  void _scheduleListenersUpdate(BuildContext context, CoilSubscription sub) {
    WidgetsBinding.instance.endOfFrame.then(
      (_) => _listeners.update(
        context,
        (subs) => subs..add(sub),
        ifAbsent: () => {sub},
      ),
    );
  }

  void _scheduleListenersCleanup(BuildContext context) {
    scheduleMicrotask(
      () => this
        .._listeners[context]?.forEach((sub) => sub.dispose())
        .._listeners.remove(context),
    );
  }

  @override
  void dispose() {
    for (final key in _listeners.keys) {
      _scheduleListenersCleanup(key);
    }
    _listeners.clear();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CoilScopeMarker(
      key: ObjectKey(_scope),
      state: this,
      child: widget.child,
    );
  }
}

class _CoilScopeMarker extends InheritedWidget {
  const _CoilScopeMarker({
    super.key,
    required this.state,
    required super.child,
  });

  final _CoilScopeState state;

  @override
  bool updateShouldNotify(_CoilScopeMarker oldWidget) => oldWidget.state._scope != state._scope;
}

extension CoilExtension on BuildContext {
  T get<T>(Coil<T> coil, {bool listen = true}) {
    final state = CoilScope._of(this);
    if (!listen) {
      return state._scope.get(coil, listen: false);
    }

    return this.listen(coil, (_, __) {
      if (this case final Element element when element.debugIsActive) {
        element.markNeedsBuild();
      } else {
        state._scheduleListenersCleanup(this);
      }
    }).get();
  }

  void mutate<T>(Coil<T> coil, CoilMutation<T> updater) => CoilScope._of(this)._scope.mutate<T>(coil, updater);

  CoilSubscription<T> listen<T>(
    Coil<T> coil,
    CoilListener<T> listener, {
    bool fireImmediately = false,
  }) {
    final state = CoilScope._of(this).._scheduleListenersCleanup(this);

    final sub = state._scope.listen(
      coil,
      listener,
      fireImmediately: fireImmediately,
    );

    state._scheduleListenersUpdate(this, sub);

    return sub;
  }

  void invalidate<T>(Coil<T> coil) => CoilScope._of(this)._scope.invalidate(coil);
}
