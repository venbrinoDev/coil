import 'package:meta/meta.dart';

typedef VoidCallback = void Function();
typedef ValueCallback<T> = T Function();
typedef CoilFactory<T> = T Function(Ref<T> ref);
typedef CoilMutation<T> = T Function(T value);
typedef CoilListener<T> = void Function(T? previous, T next);
typedef CoilSubscription<T> = ({ValueCallback<T> get, VoidCallback dispose});
typedef CoilFamily<U, V extends Coil> = V Function(U arg);
typedef CoilFamilyFactory<T, U> = T Function(Ref ref, U arg);

@optionalTypeArgs
abstract class Ref<U> {
  T get<T>(
    Coil<T> coil, {
    bool listen = true,
  });

  T mutate<T>(Coil<T> coil, CoilMutation<T> updater);

  U? mutateSelf(CoilMutation<U?> updater);

  CoilSubscription<T> listen<T>(
    Coil<T> coil,
    CoilListener<T> listener, {
    bool fireImmediately = false,
  });

  void invalidate<T>(Coil<T> coil);

  void onDispose(VoidCallback callback);
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
class Scope<U> implements Ref<U> {
  Scope()
      : _owner = null,
        _elements = {};

  Scope._(CoilElement<U>? owner, Scope parent)
      : _owner = owner,
        _elements = parent._elements;

  final CoilElement<U>? _owner;
  final Map<Coil, CoilElement> _elements;

  VoidCallback? _onDispose;

  @override
  T get<T>(Coil<T> coil, {bool listen = true}) => _resolve(coil, listen: listen).state;

  @override
  T mutate<T>(Coil<T> coil, CoilMutation<T> updater) {
    final element = _resolve(coil);
    return element.state = updater(element.state);
  }

  @override
  @protected
  U? mutateSelf(CoilMutation<U?> updater) {
    if (updater(_owner?._state) case final state? when _owner != null) {
      return _owner?.state = state;
    }
    return null;
  }

  @override
  CoilSubscription<T> listen<T>(
    Coil<T> coil,
    CoilListener<T> listener, {
    bool fireImmediately = false,
  }) {
    final element = _resolve(coil, mount: false);
    final dispose = element._addListener(listener);

    final previousState = element._state;
    _mount(element);

    if (fireImmediately) {
      listener(previousState, element.state);
    }

    return (
      get: () => element.state,
      dispose: dispose,
    );
  }

  @override
  void invalidate<T>(Coil<T> coil) => _elements[coil]?._invalidate();

  @override
  void onDispose(VoidCallback callback) {
    if (_owner case final owner?) {
      final previousCallback = owner._onDispose;
      owner._onDispose = () {
        previousCallback?.call();
        callback();
      };
    } else {
      final previousCallback = _onDispose;
      _onDispose = () {
        previousCallback?.call();
        callback();
      };
    }
  }

  void dispose() {
    _onDispose?.call();
    _elements
      ..forEach((_, element) => element._dispose())
      ..clear();
  }

  CoilElement<T> _resolve<T>(Coil<T> coil, {bool mount = true, bool listen = false}) {
    switch (_elements[coil]) {
      case CoilElement<T> element:
        if (listen) {
          _owner?._dependsOn(element);
        }

        return element;
      case _:
        final element = coil.createElement();
        _elements[coil] = element;

        if (listen) {
          _owner?._dependsOn(element);
        }

        if (mount) {
          _mount(element);
        }

        return element;
    }
  }

  void _mount<T>(CoilElement<T> element) {
    element
      .._scope = Scope._(element, this)
      .._mount();
  }
}

@optionalTypeArgs
class CoilElement<T> {
  CoilElement(this._coil);

  final Coil<T> _coil;
  final Set<CoilListener<T>> _listeners = {};
  final Set<CoilElement> _dependents = {};

  Scope<T>? _scope;
  VoidCallback? _onDispose;

  T get state {
    assert(_state != null, 'Needs to have its state set at least once');
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

  void _mount() {
    if (_scope case final scope?) {
      final oldState = _state;
      _state = _coil.factory(scope);

      if (oldState != null && oldState != _state) {
        _notifyListeners(oldState);
      }
    }
  }

  void _invalidate() {
    _mount();
    _invalidateDependents();
  }

  VoidCallback _addListener(CoilListener<T> listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _dependsOn(CoilElement element) => element._dependents.add(this);

  void _notifyListeners(T? oldState) {
    for (final listener in _listeners) {
      listener(oldState, state);
    }
  }

  void _invalidateDependents() {
    for (final dependent in _dependents) {
      dependent._mount();
    }
  }

  void _dispose() {
    _state = null;
    _scope = null;
    _onDispose?.call();
    _listeners.clear();
    _dependents.clear();
  }

  @override
  String toString() {
    if (_coil.debugName case final debugName?) {
      return 'CoilElement($debugName)';
    }

    return runtimeType.toString();
  }
}
