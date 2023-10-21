import 'package:meta/meta.dart';

abstract class Ref {
  T get<T>(Coil<T> coil);

  void mutate<T>(MutableCoil<T> coil, T Function(T value) updater);

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Coil && runtimeType == other.runtimeType && _key == other._key;

  @override
  int get hashCode => _key.hashCode;
}

class Scope implements Ref {
  Scope()
      : _owner = null,
        _elements = {};

  Scope._({required CoilElement owner, required Map<Coil, CoilElement> bucket})
      : _owner = owner,
        _elements = bucket;

  late final CoilElement? _owner;
  final Map<Coil, CoilElement> _elements;

  @override
  T get<T>(Coil<T> coil) => _resolve(coil).state;

  @override
  void mutate<T>(MutableCoil<T> coil, T Function(T value) updater) {
    final state = get(coil.state);
    state.value = updater(state.value);
  }

  @override
  CoilSubscription<T> listen<T>(MutableCoil<T> coil, CoilListener<T> listener) {
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

  CoilElement<T> _resolve<T>(Coil<T> coil) {
    switch (_elements[coil]) {
      case final CoilElement<T> element:
        _owner?._dependOn(element);
        return element;
      case _:
        final CoilElement<T> element = coil.createElement()
          .._coil = coil
          .._scope = this;
        element.state = coil._factory(_clone(element));
        _elements[coil] = element;
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
    _scope._elements.remove(_coil);
    _invalidateDependents();
    _dependents.clear();
  }

  void Function() _addListener(CoilListener<T> listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
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
class MutableCoil<T> extends ValueCoil<T> {
  MutableCoil(super.factory, {super.debugName});

  late final state = _StateCoil(this, debugName: '${debugName}State');
}

@optionalTypeArgs
class _StateCoil<T> extends Coil<_CoilState<T>> {
  _StateCoil(MutableCoil<T> parent, {String? debugName})
      : super._(
          (Ref ref) => _CoilState(
            () => (ref as Scope)._resolve(parent).state,
            (value) => (ref as Scope)._resolve(parent).state = value,
          ),
          debugName: debugName,
        );

  @override
  CoilElement<_CoilState<T>> createElement() => CoilElement<_CoilState<T>>();
}

class _CoilState<T> {
  _CoilState(this._factory, this._onUpdate);

  final T Function() _factory;
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
  String toString() => 'CoilState($_value)';
}
