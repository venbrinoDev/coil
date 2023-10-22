import 'dart:async';

import 'package:meta/meta.dart';

typedef VoidCallback = void Function();
typedef ValueCallback<T> = T Function();
typedef CoilFactory<T> = T Function(Ref ref);
typedef CoilMutation<T> = T Function(T value);
typedef CoilListener<T> = void Function(T? previous, T next);
typedef CoilSubscription<T> = ({ValueCallback<T> get, VoidCallback dispose});

abstract class Ref {
  T get<T>(Coil<T> coil);

  void mutate<T>(MutableCoil<T> coil, CoilMutation<T> updater);

  CoilSubscription<T> listen<T>(ListenableCoil<T> coil, CoilListener<T> listener);

  void invalidate<T>(Coil<T> coil);
}

@optionalTypeArgs
base class Coil<T> {
  Coil._(this._factory, {this.debugName});

  factory Coil(CoilFactory<T> factory, {String? debugName}) = ValueCoil;

  final String? debugName;

  final CoilFactory<T> _factory;

  CoilElement<T> createElement() => CoilElement<T>();

  @override
  bool operator ==(Object other) => identical(this, other) || other is Coil && runtimeType == other.runtimeType;

  @override
  int get hashCode => identityHashCode(this);

  @override
  String toString() => 'Coil($debugName)[$hashCode]';
}

base mixin ListenableCoil<T> on Coil<T> {}
base mixin AsyncListenableCoil<T> implements ListenableCoil<AsyncValue<T>> {}

class Scope implements Ref {
  Scope()
      : _owner = null,
        _parent = null,
        _elements = {};

  Scope._({
    required CoilElement owner,
    required Scope parent,
  })  : _owner = owner,
        _parent = parent,
        _elements = parent._elements;

  final CoilElement? _owner;
  final Scope? _parent;
  final Map<Coil, CoilElement> _elements;

  @override
  T get<T>(Coil<T> coil) => _resolve(coil).state;

  @override
  void mutate<T>(MutableCoil<T> coil, CoilMutation<T> updater) {
    final state = get(coil.state);
    state.value = updater(state.value);
  }

  @override
  CoilSubscription<T> listen<T>(ListenableCoil<T> coil, CoilListener<T> listener) {
    final element = _resolve(coil, mount: false);
    final dispose = element._addListener(listener);
    _mount(element, coil);

    return (
      get: () => element.state,
      dispose: dispose,
    );
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    if (_elements[coil] case final element?) {
      _elements.remove(coil);
      element._invalidate();
    }
  }

  void dispose() {
    if (_owner case final owner?) {
      _unmount(owner);
    } else {
      _elements
        ..values.forEach(_unmount)
        ..clear();
    }
  }

  CoilElement<T> _resolve<T>(Coil<T> coil, {bool mount = true, bool listen = true}) {
    switch (_elements[coil]) {
      case final CoilElement<T> element?:
        if (listen) {
          _owner?._dependOn(element);
        }
        return element;
      case _:
        final CoilElement<T> element = coil.createElement();
        if (listen) {
          _owner?._dependOn(element);
        }
        if (mount) {
          _mount(element, coil);
        }

        return element;
    }
  }

  void _mount<T>(CoilElement element, Coil<T> coil) {
    _elements[coil] = element;
    element
      .._coil = coil
      .._scope ??= Scope._(owner: element, parent: this)
      .._mount();
  }

  void _unmount(CoilElement element) {
    if (element._coil case final coil?) {
      _elements.remove(coil);
      element.dispose();
    }
  }
}

@optionalTypeArgs
class CoilElement<T> {
  Scope? _scope;
  Coil<T>? _coil;

  final Set<CoilListener<T>> _listeners = {};
  final Set<CoilElement> _dependents = {};
  final Set<VoidCallback> _subscriptions = {};

  T get state => _state!;
  T? _state;

  set state(T value) {
    if (_state != value) {
      final oldState = _state;
      _state = value;
      _notifyListeners(oldState);
      _invalidateDependents();
    }
  }

  void dispose() {
    _state = null;
    _coil = null;
    _scope = null;
    _invalidateSubscriptions();
    _subscriptions.clear();
    _listeners.clear();
    _dependents.clear();
  }

  void _mount() {
    if (_scope case final scope?) {
      _state = _coil?._factory(scope);
    }
  }

  void _invalidate() {
    if (_listeners.isEmpty && _dependents.isEmpty) {
      _scope?._elements.remove(_coil);
    }
    _invalidateSubscriptions();
    _invalidateDependents();
    _subscriptions.clear();
    _dependents.clear();

    Future(() => _mount());
  }

  VoidCallback _addListener(CoilListener<T> listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _addSubscription(VoidCallback subscription) => _subscriptions.add(subscription);

  void _dependOn(CoilElement element) => element._dependents.add(this);

  void _notifyListeners(T? oldState) {
    for (final listener in _listeners.toList(growable: false)) {
      listener(oldState, state);
    }
  }

  void _invalidateDependents() {
    for (final element in _dependents) {
      element._invalidate();
    }
  }

  void _invalidateSubscriptions() {
    for (final disposer in _subscriptions) {
      disposer();
    }
  }

  @override
  String toString() {
    if (_coil?.debugName case final debugName?) {
      return 'CoilElement($debugName)';
    }

    return runtimeType.toString();
  }
}

@optionalTypeArgs
final class ValueCoil<T> extends Coil<T> {
  ValueCoil(super.factory, {super.debugName}) : super._();
}

@optionalTypeArgs
final class MutableCoil<T> extends Coil<T> with ListenableCoil<T> {
  MutableCoil(super.factory, {super.debugName}) : super._();

  late final state = StateCoil(this, debugName: '$debugName-state');
}

@optionalTypeArgs
base class _AsyncValueCoil<T, U> extends Coil<AsyncValue<T>> with AsyncListenableCoil<T> {
  _AsyncValueCoil(super.factory, {super.debugName}) : super._();

  late final future = AsyncCoil(this, debugName: '$debugName-future');
}

@optionalTypeArgs
final class FutureCoil<T> extends _AsyncValueCoil<T, FutureOr<T>> {
  FutureCoil(CoilFactory<FutureOr<T>> factory, {super.debugName})
      : super((Ref ref) {
          switch (factory(ref)) {
            case T value:
              return AsyncSuccess<T>(value);
            case Future<T> future:
              future.then(
                (value) => (ref as Scope)._owner?.state = AsyncSuccess<T>(value),
              );
              return AsyncLoading<T>();
          }
        });
}

@optionalTypeArgs
final class StreamCoil<T> extends _AsyncValueCoil<T, Stream<T>> {
  StreamCoil(CoilFactory<Stream<T>> factory, {super.debugName})
      : super((Ref ref) {
          if ((ref as Scope)._owner case final element?) {
            element._invalidateSubscriptions();
            final sub = factory(ref).listen(
              (value) => element.state = AsyncSuccess<T>(value),
            );
            element._addSubscription(() => sub.cancel());
          }
          return AsyncLoading<T>();
        });
}

@optionalTypeArgs
final class StateCoil<T> extends Coil<_CoilState<T>> {
  StateCoil(MutableCoil<T> parent, {super.debugName})
      : super._((Ref ref) {
          final scope = (ref as Scope);
          return _CoilState(
            () => scope._resolve(parent).state,
            (value) => scope._resolve(parent).state = value,
          );
        });
}

@optionalTypeArgs
final class AsyncCoil<T> extends Coil<Future<T>> {
  AsyncCoil(AsyncListenableCoil<T> parent, {super.debugName})
      : super._((Ref ref) {
          if ((ref as Scope)._owner case final element?) {
            final parentElement = ref._resolve(parent, listen: false);

            // Create relationship between host and parent elements
            ref._parent?._owner?._dependOn(parentElement);

            if (parentElement.state case AsyncSuccess<T>(:final value)) {
              return Future.value(value);
            }

            final completer = Completer<T>();

            element._addSubscription(
              parentElement._addListener((_, next) {
                switch (next) {
                  case AsyncLoading<T>() || AsyncFailure<T>():
                    break;
                  case AsyncSuccess<T>(:final value):
                    completer.complete(value);
                    ref._unmount(element);
                }
              }),
            );

            return completer.future;
          }

          return Completer<T>().future;
        });
}

class _CoilState<T> {
  _CoilState(this._factory, this._onUpdate);

  final ValueCallback<T> _factory;
  final void Function(T value) _onUpdate;

  T get value => _value;
  late T _value = _factory();

  set value(T value) {
    if (value != _value) {
      _value = value;
      _onUpdate(_value);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _CoilState && runtimeType == other.runtimeType && _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'CoilState($_value)';
}

sealed class AsyncValue<T> {
  const AsyncValue();
}

class AsyncLoading<T> implements AsyncValue<T> {
  const AsyncLoading();

  @override
  String toString() => 'AsyncLoading<$T>()';
}

class AsyncSuccess<T> implements AsyncValue<T> {
  const AsyncSuccess(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AsyncSuccess && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AsyncSuccess<$T>($value)';
}

class AsyncFailure<T> implements AsyncValue<T> {
  const AsyncFailure();

  @override
  String toString() => 'AsyncFailure<$T>()';
}
