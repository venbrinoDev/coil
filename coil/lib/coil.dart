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
sealed class Coil<T> {
  Coil._(this._factory, {this.debugName});

  factory Coil(CoilFactory<T> factory, {String? debugName}) = ValueCoil;

  final String? debugName;

  final CoilFactory<T> _factory;

  CoilElement<T> createElement();

  @override
  bool operator ==(Object other) => identical(this, other) || other is Coil && runtimeType == other.runtimeType;

  @override
  int get hashCode => identityHashCode(this);

  @override
  String toString() => 'Coil($debugName)[$hashCode]';
}

mixin ListenableCoil<T> on Coil<T> {}

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
    final element = _resolve(coil);
    final dispose = element._addListener(listener);

    return (
      get: () => element.state,
      dispose: dispose,
    );
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    if (_elements[coil] case final element?) {
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

  CoilElement<T> _resolve<T>(Coil<T> coil) {
    switch (_elements[coil]) {
      case final CoilElement<T> element?:
        _owner?._dependOn(element);
        return element;
      case _:
        final CoilElement<T> element = coil.createElement()
          .._coil = coil
          .._scope = this;
        _elements[coil] = element..state = coil._factory(_clone(element));
        _owner?._dependOn(element);

        return element;
    }
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
    _scope?._elements.remove(_coil);
    _invalidateSubscriptions();
    _invalidateDependents();
    _subscriptions.clear();
    _dependents.clear();

    // Future(() => _scope?._resolve(_coil!));
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
class ValueCoil<T> extends Coil<T> {
  ValueCoil(super.factory, {super.debugName}) : super._();

  @override
  CoilElement<T> createElement() => CoilElement<T>();
}

@optionalTypeArgs
class MutableCoil<T> extends ValueCoil<T> with ListenableCoil<T> {
  MutableCoil(super.factory, {super.debugName});

  late final state = _StateCoil(this, debugName: '${debugName}State');
}

@optionalTypeArgs
class FutureCoil<T> extends Coil<AsyncValue<T>> with ListenableCoil<AsyncValue<T>> {
  FutureCoil(CoilFactory<FutureOr<T>> factory, {super.debugName})
      : super._(
          (Ref ref) {
            switch (factory(ref)) {
              case T value:
                return AsyncSuccess<T>(value);
              case Future<T> future:
                future.then(
                  (value) => (ref as Scope)._owner?.state = AsyncSuccess<T>(value),
                );
                return AsyncLoading<T>();
            }
          },
        );

  @override
  CoilElement<AsyncValue<T>> createElement() => CoilElement<AsyncValue<T>>();
}

@optionalTypeArgs
class StreamCoil<T> extends Coil<AsyncValue<T>> with ListenableCoil<AsyncValue<T>> {
  StreamCoil(CoilFactory<Stream<T>> factory, {super.debugName})
      : super._(
          (Ref ref) {
            if ((ref as Scope)._owner case final element?) {
              element._invalidateSubscriptions();
              final sub = factory(ref).listen(
                (value) => element.state = AsyncSuccess<T>(value),
              );
              element._addSubscription(() => sub.cancel());
            }
            return AsyncLoading<T>();
          },
        );

  late final future = _FutureCoil(this, debugName: '${debugName}Future');

  @override
  CoilElement<AsyncValue<T>> createElement() => CoilElement<AsyncValue<T>>();
}

@optionalTypeArgs
class _StateCoil<T> extends Coil<_CoilState<T>> {
  _StateCoil(MutableCoil<T> parent, {super.debugName})
      : super._(
          (Ref ref) => _CoilState(
            () => (ref as Scope)._resolve(parent).state,
            (value) => (ref as Scope)._resolve(parent).state = value,
          ),
        );

  @override
  CoilElement<_CoilState<T>> createElement() => CoilElement<_CoilState<T>>();
}

@optionalTypeArgs
class _FutureCoil<T> extends Coil<Future<T>> {
  _FutureCoil(StreamCoil<T> parent, {super.debugName})
      : super._(
          (Ref ref) {
            final completer = Completer<T>();
            if ((ref as Scope)._owner case final element?) {
              element._invalidateSubscriptions();
              final sub = ref.listen(
                parent,
                (_, next) => switch (next) {
                  AsyncLoading<T>() || AsyncFailure<T>() => null,
                  AsyncSuccess<T>(:final value) => completer.complete(value),
                },
              );
              element._addSubscription(() => sub.dispose());
            }
            return completer.future;
          },
        );

  @override
  CoilElement<Future<T>> createElement() => CoilElement<Future<T>>();
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
