import 'dart:async';

import 'package:meta/meta.dart';

typedef VoidCallback = void Function();
typedef ValueCallback<T> = T Function();
typedef CoilFactory<T> = T Function(Ref ref);
typedef CoilMutation<T> = T Function(T value);
typedef CoilListener<T> = void Function(T? previous, T next);
typedef CoilSubscription<T> = ({ValueCallback<T> get, VoidCallback dispose});
typedef CoilFamily<U, V extends Coil> = V Function(U arg);
typedef CoilFamilyFactory<T, U> = T Function(Ref ref, U arg);

abstract class Ref {
  T get<T>(
    Coil<T> coil, {
    bool listen = true,
  });

  CoilSubscription<T> listen<T>(
    Coil<T> coil,
    CoilListener<T> listener, {
    bool fireImmediately = false,
  });

  void invalidate<T>(Coil<T> coil);
}

@optionalTypeArgs
base class Coil<T> {
  Coil(this.factory, {this.key, this.debugName});

  static CoilFamily<U, Coil<T>> family<T, U>(
    CoilFamilyFactory<T, U> factory, {
    String? debugName,
  }) {
    return (U arg) => Coil((ref) => factory(ref, arg), key: arg, debugName: debugName);
  }

  @internal
  final CoilFactory<T> factory;

  @internal
  final Object? key;

  @internal
  final String? debugName;

  CoilElement<T> createElement() => CoilElement<T>(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Coil && runtimeType == other.runtimeType && key == other.key;

  @override
  int get hashCode => key?.hashCode ?? identityHashCode(this);

  @override
  String toString() => 'Coil($debugName)[$hashCode]';
}

@optionalTypeArgs
final class MutableCoil<T> extends Coil<T> {
  MutableCoil(super.factory, {super.key, super.debugName});

  static CoilFamily<U, MutableCoil<T>> family<T, U>(
    CoilFamilyFactory<T, U> factory, {
    String? debugName,
  }) {
    return (U arg) => MutableCoil((ref) => factory(ref, arg), key: arg, debugName: debugName);
  }

  late final state = StateCoil(this, debugName: '$debugName-state');
}

@optionalTypeArgs
base class AsyncValueCoil<T> extends Coil<AsyncValue<T>> {
  AsyncValueCoil(super.factory, {super.key, super.debugName});

  late final async = AsyncCoil(this, debugName: '$debugName-async');

  static AsyncLoading<T> _enrichLoadingState<T>(CoilElement? element) {
    return switch (element?._state) {
      AsyncSuccess<T>(:final T value) || AsyncLoading<T>(:final T value) => AsyncLoading<T>(value),
      _ => AsyncLoading<T>()
    };
  }
}

@optionalTypeArgs
final class FutureCoil<T> extends AsyncValueCoil<T> {
  FutureCoil(CoilFactory<FutureOr<T>> factory, {super.key, super.debugName})
      : super((Ref ref) {
          switch (factory(ref)) {
            case T value:
              return AsyncSuccess<T>(value);
            case Future<T> future:
              final element = (ref as Scope)._owner;
              if (element != null) {
                element
                  .._invalidateSubscriptions()
                  .._addSubscription(
                    future.then((value) {
                      element.state = AsyncSuccess<T>(value);
                    }).catchError((Object error, StackTrace stackTrace) {
                      element.state = AsyncFailure<T>(error, stackTrace);
                    }).ignore,
                  );
              }

              return AsyncValueCoil._enrichLoadingState<T>(element);
          }
        });

  static CoilFamily<U, FutureCoil<T>> family<T, U>(
    CoilFamilyFactory<FutureOr<T>, U> factory, {
    String? debugName,
  }) {
    return (U arg) => FutureCoil((ref) => factory(ref, arg), key: arg, debugName: debugName);
  }
}

@optionalTypeArgs
final class StreamCoil<T> extends AsyncValueCoil<T> {
  StreamCoil(CoilFactory<Stream<T>> factory, {super.key, super.debugName})
      : super((Ref ref) {
          final element = (ref as Scope)._owner;
          if (element != null) {
            element
              .._invalidateSubscriptions()
              .._addSubscription(
                factory(ref).listen((value) {
                  element.state = AsyncSuccess<T>(value);
                }, onError: (Object error, StackTrace stackTrace) {
                  element.state = AsyncFailure(error, stackTrace);
                }).cancel,
              );
          }

          return AsyncValueCoil._enrichLoadingState<T>(element);
        });

  static CoilFamily<U, StreamCoil<T>> family<T, U>(
    CoilFamilyFactory<Stream<T>, U> factory, {
    String? debugName,
  }) {
    return (U arg) => StreamCoil((ref) => factory(ref, arg), key: arg, debugName: debugName);
  }
}

typedef _ProxyCoilRef<T> = ({
  CoilElement<T> parent,
  CoilElement element,
  VoidCallback unmount,
});
typedef _ProxyCoilFactory<T, U> = U Function(_ProxyCoilRef<T> ref);

@optionalTypeArgs
base class _ProxyCoil<T, U> extends Coil<U> {
  _ProxyCoil(Coil<T> parent, _ProxyCoilFactory<T, U> factory, {super.debugName})
      : super((Ref ref) {
          final element = (ref as Scope)._owner;
          if (element == null) {
            throw AssertionError('Failed to mount :(');
          }

          // Create relationship between host and parent elements
          final parentElement = ref._resolve(parent);
          ref._parent?._owner?._dependOn(parentElement);

          return factory(
            (
              parent: parentElement,
              element: element,
              unmount: () => ref._unmount(element),
            ),
          );
        });
}

@optionalTypeArgs
final class StateCoil<T> extends _ProxyCoil<T, _CoilState<T>> {
  StateCoil(MutableCoil<T> parent, {super.debugName})
      : super(parent, (ref) {
          return _CoilState(
            () => ref.parent.state,
            (value) => ref
              ..parent.state = value
              ..unmount(),
          );
        });
}

@optionalTypeArgs
final class AsyncCoil<T> extends _ProxyCoil<AsyncValue<T>, Future<T>> {
  AsyncCoil(AsyncValueCoil<T> parent, {super.debugName})
      : super(parent, (ref) {
          final completer = Completer<T>();

          void resolve(T value) {
            completer.complete(value);
            ref.unmount();
          }

          void resolveError(Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
            ref.unmount();
          }

          if (ref.parent.state case AsyncSuccess<T>(:final value)) {
            resolve(value);
          } else {
            ref.element
              .._invalidateSubscriptions()
              .._addSubscription(
                ref.parent._addListener(
                  (_, next) => switch (next) {
                    AsyncLoading<T>() => null,
                    AsyncFailure<T>(:final error, :final stackTrace) => resolveError(error, stackTrace),
                    AsyncSuccess<T>(:final value) => resolve(value),
                  },
                ),
              );
          }

          return completer.future;
        });
}

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

  @visibleForTesting
  Map<Coil, CoilElement> get elements => _elements;

  @override
  T get<T>(Coil<T> coil, {bool listen = true}) => _resolve(coil, listen: listen).state;

  @override
  CoilSubscription<T> listen<T>(
    Coil<T> coil,
    CoilListener<T> listener, {
    bool fireImmediately = false,
  }) {
    final element = _resolve(coil, mount: false);
    final dispose = element._addListener(listener);
    if (!element.mounted) {
      _mount(element);
    }
    if (fireImmediately) {
      listener(null, element.state);
    }

    return (
      get: () => element.state,
      dispose: dispose,
    );
  }

  @override
  void invalidate<T>(Coil<T> coil) => _elements[coil]?._invalidate();

  void dispose() {
    if (_owner case final owner?) {
      _unmount(owner);
    } else {
      _elements
        ..values.forEach(_unmount)
        ..clear();
    }
  }

  CoilElement<T> _resolve<T>(Coil<T> coil, {bool mount = true, bool listen = false}) {
    switch (_elements[coil]) {
      case final CoilElement<T> element?:
        if (listen) {
          _owner?._dependOn(element);
        }
        if (!element.mounted) {
          _mount(element);
        }
        return element;
      case _:
        final CoilElement<T> element = coil.createElement();
        if (listen) {
          _owner?._dependOn(element);
        }
        if (mount) {
          _mount(element);
        }

        return element;
    }
  }

  void _mount<T>(CoilElement element) {
    _elements[element._coil] = element;
    element
      .._scope ??= Scope._(owner: element, parent: this)
      .._mount();
  }

  void _unmount(CoilElement element) {
    _elements.remove(element._coil);
    element.dispose();
  }
}

@optionalTypeArgs
class CoilElement<T> {
  CoilElement(this._coil);

  final Coil<T> _coil;
  final Set<CoilListener<T>> _listeners = {};
  final Set<CoilElement> _dependents = {};
  final Set<VoidCallback> _subscriptions = {};

  Scope? _scope;

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

  bool get mounted => _state != null;

  void dispose() {
    _state = null;
    _scope = null;
    _invalidateSubscriptions();
    _subscriptions.clear();
    _listeners.clear();
    _dependents.clear();
  }

  void _mount() {
    if (_scope case final scope?) {
      state = _coil.factory(scope);
    }
  }

  void _invalidate() {
    _invalidateSubscriptions();
    _subscriptions.clear();

    if (_listeners.isEmpty && _dependents.isEmpty) {
      _scope?._unmount(this);
    } else {
      _mount(); //todo: maybe scheduler?
    }
  }

  VoidCallback _addListener(CoilListener<T> listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _addSubscription(VoidCallback subscription) => _subscriptions.add(subscription);

  void _dependOn(CoilElement element) => element._dependents.add(this);

  void _notifyListeners(T? oldState) {
    for (final listener in [..._listeners]) {
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
    if (_coil.debugName case final debugName?) {
      return 'CoilElement($debugName)';
    }

    return runtimeType.toString();
  }
}

class _CoilState<T> {
  _CoilState(this._factory, this._onUpdate);

  final ValueCallback<T> _factory;
  final void Function(T value) _onUpdate;

  T get value => _factory();

  set value(T value) => _onUpdate(value);

  @override
  String toString() => 'CoilState($value)';
}

sealed class AsyncValue<T> {
  const AsyncValue();
}

class AsyncLoading<T> implements AsyncValue<T> {
  const AsyncLoading([this.value]);

  final T? value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AsyncLoading && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AsyncLoading<$T>${value != null ? '($value)' : ''}';
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
  const AsyncFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AsyncFailure && runtimeType == other.runtimeType && error == other.error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'AsyncFailure<$T>($error)';
}
