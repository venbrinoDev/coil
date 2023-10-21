import 'package:meta/meta.dart';

abstract class Ref {
  T get<T>(Coil<T> coil);

  CoilSubscription<T> listen<T>(MutableCoil<T> coil, CoilListener<T> listener);

  void invalidate<T>(Coil<T> coil);
}

typedef CoilFactory<T> = T Function(Ref ref);
typedef CoilListener<T> = void Function(T? previous, T next);
typedef CoilSubscription<T> = ({T Function() get, Function() dispose});

@optionalTypeArgs
sealed class Coil<T> {
  Coil._(this._factory, {this.debugName});

  factory Coil(CoilFactory<T> factory, {String? debugName}) = ValueCoil;

  final String? debugName;

  final CoilFactory<T> _factory;

  late final int _key = identityHashCode(this);

  CoilElement<T> createElement();
}

class Scope implements Ref {
  Scope()
      : _owner = null,
        _elements = {};

  Scope._({required CoilElement owner, required Map<int, CoilElement> bucket})
      : _owner = owner,
        _elements = bucket;

  late final CoilElement? _owner;
  final Map<int, CoilElement> _elements;

  @override
  T get<T>(Coil<T> coil) => _resolve(coil).state;

  @override
  CoilSubscription<T> listen<T>(MutableCoil<T> coil, CoilListener<T> listener) {
    void fn(CoilState<T>? previous, CoilState<T> next) => listener(previous?.value, next.value);
    final element = _resolve(coil).._listeners.add(fn);

    return (
      get: () => element.state.value,
      dispose: () => element._listeners.remove(fn),
    );
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    if (_elements[coil._key] case final element?) {
      element.invalidate();
    }
  }

  CoilElement<T> _resolve<T>(Coil<T> coil) {
    switch (_elements[coil._key]) {
      case final CoilElement<T> element?:
        _owner?._dependOn(element);
        return element;
      case _:
        final CoilElement<T> element = coil.createElement()
          .._coil = coil
          .._scope = this;
        element.state = coil._factory(_clone(element));
        _elements[coil._key] = element;
        _owner?._dependOn(element);

        return element;
    }
  }

  Scope _clone(CoilElement owner) => Scope._(owner: owner, bucket: {..._elements});
}

@optionalTypeArgs
class CoilElement<T> {
  late final Scope _scope;
  late final Coil _coil;

  final Set<CoilListener<T>> _listeners = {};
  final Set<CoilElement> _dependents = {};

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
    _invalidateDependents();
    _scope._elements.remove(_coil._key);
    _dependents.clear();
  }

  void _dependOn(CoilElement element) => element._dependents.add(this);

  void _notifyListeners(T? oldState) {
    for (final listener in _listeners) {
      listener(oldState, state);
    }
  }

  void _invalidateDependents() {
    for (final element in _dependents) {
      element.invalidate();
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

@optionalTypeArgs
class ValueCoil<T> extends Coil<T> {
  ValueCoil(super.factory, {super.debugName}) : super._();

  @override
  CoilElement<T> createElement() => CoilElement<T>();
}

@optionalTypeArgs
class MutableCoil<T> extends Coil<CoilState<T>> {
  MutableCoil(CoilFactory<T> factory, {String? debugName})
      : super._(
          (Ref ref) => CoilState(
            () => factory(ref),
            (state, value) {
              if ((ref as Scope)._owner case final element?) {
                final previousState = element.state;
                element._invalidateDependents();
                element._notifyListeners(previousState);
              }
            },
          ),
          debugName: debugName,
        );

  @override
  CoilElement<CoilState<T>> createElement() => CoilElement<CoilState<T>>();
}

class CoilState<T> {
  CoilState(this._factory, this._onUpdate);

  final T Function() _factory;
  final void Function(CoilState<T> state, T value) _onUpdate;

  T get value => _value;
  late T _value = _factory();

  set value(T value) {
    if (value != _value) {
      _value = value;
      _onUpdate(this, _value);
    }
  }

  @override
  String toString() => 'CoilState($_value)';
}
