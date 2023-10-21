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
        _elements = {};

  Scope._({required CoilElement owner, required Map<Coil, CoilElement> bucket})
      : _owner = owner,
        _elements = bucket;

  final CoilElement? _owner;
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
    _mount(element);

    return (
      get: () => element.state,
      dispose: dispose,
    );
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    if (_elements[coil] case final element?) {
      _elements.remove(coil);
      element.invalidate();
    }
  }

  void dispose() {
    _owner?.invalidate();
    if (_owner == null) {
      _elements
        ..forEach((_, element) => element.dispose())
        ..clear();
    }
  }

  CoilElement<T> _resolve<T>(Coil<T> coil, {bool mount = true}) {
    switch (_elements[coil]) {
      case final CoilElement<T> element?:
        _owner?._dependOn(element);
        return element;
      case _:
        final CoilElement<T> element = coil.createElement().._coil = coil;
        _elements[coil] = element;
        _owner?._dependOn(element);
        if (mount) {
          _mount(element);
        }
        return element;
    }
  }

  void _mount(CoilElement element, [Scope? override]) {
    final scope = override ?? _clone(element);
    element
      .._scope = scope
      .._state = element._coil?._factory(scope);
  }

  Scope _clone(CoilElement owner) => Scope._(owner: owner, bucket: _elements);
}

@optionalTypeArgs
class CoilElement<T> {
  late Scope? _scope;
  late Coil? _coil;

  final Set<CoilListener<T>> _listeners = {};
  final Set<CoilElement> _dependents = {};
  final Set<VoidCallback> _subscriptions = {};

  T get state {
    assert(_state != null, 'Should set the state');
    return _state!;
  }

  T? _state;

  set state(T value) {
    if (_state != value) {
      final oldState = _state;
      _state = value;
      _notifyListeners(oldState);
      _invalidateDependents();
    }
  }

  void invalidate() {
    if (_listeners.isEmpty && _dependents.isEmpty) {
      _scope?._elements.remove(_coil);
    }
    _invalidateSubscriptions();
    _invalidateDependents();
    _subscriptions.clear();
    _dependents.clear();

    Future(() => _scope?._mount(this, _scope));
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

  VoidCallback _addListener(CoilListener<T> listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _addSubscription(VoidCallback subscription) => _subscriptions.add(subscription);

  void _dependOn(CoilElement element) => element._dependents.add(this);

  void _notifyListeners(T? oldState) {
    for (final listener in _listeners) {
      listener(oldState, state);
    }
  }

  void _invalidateDependents() {
    for (final element in [..._dependents].reversed) {
      element.invalidate();
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

  late final state = _StateCoil(this, debugName: '$debugName-state');
}

@optionalTypeArgs
base class _AsyncCoil<T, U> extends Coil<AsyncValue<T>> with AsyncListenableCoil<T> {
  _AsyncCoil(super.factory, {super.debugName}) : super._();

  late final future = _FutureCoil(this, debugName: '$debugName-future');
}

@optionalTypeArgs
final class FutureCoil<T> extends _AsyncCoil<T, FutureOr<T>> {
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
final class StreamCoil<T> extends _AsyncCoil<T, Stream<T>> {
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
final class _StateCoil<T> extends Coil<_CoilState<T>> {
  _StateCoil(MutableCoil<T> parent, {super.debugName})
      : super._((Ref ref) {
          final scope = (ref as Scope);
          return _CoilState(
            () => scope._resolve(parent).state,
            (value) => scope._resolve(parent).state = value,
          );
        });
}

@optionalTypeArgs
final class _FutureCoil<T> extends Coil<Future<T>> {
  _FutureCoil(AsyncListenableCoil<T> parent, {super.debugName})
      : super._((Ref ref) {
          final completer = Completer<T>();
          if ((ref as Scope)._owner case final element?) {
            _resolve(completer, ref.get(parent));
            element
              .._invalidateSubscriptions()
              .._addSubscription(
                ref._resolve(parent)._addListener((_, next) => _resolve(completer, next)),
              );
          }
          return completer.future;
        });

  static void _resolve<T>(Completer<T> completer, AsyncValue<T> state) {
    return switch (state) {
      AsyncLoading<T>() || AsyncFailure<T>() => null,
      AsyncSuccess<T>(:final value) => completer.complete(value),
    };
  }
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
