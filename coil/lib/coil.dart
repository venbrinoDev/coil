import 'package:meta/meta.dart';

abstract class Ref {
  T use<T>(Coil<T> coil);

  void mutate<T>(MutableCoil<T> coil, T Function(T) updater);

  void invalidate<T>(Coil<T> coil);
}

typedef RefFactory<T> = T Function(Ref);

sealed class Coil<T> {
  Coil(this._factory, {this.debugName});

  final String? debugName;

  final RefFactory<T> _factory;

  late final int _key = identityHashCode(this);
}

mixin MutableCoil<T> on Coil<T> {}

class Scope implements Ref {
  Scope()
      : _owner = null,
        _elements = {};

  Scope._({required _CoilElement owner, required Map<int, _CoilElement> bucket})
      : _owner = owner,
        _elements = bucket;

  late final _CoilElement? _owner;
  final Map<int, _CoilElement> _elements;

  @override
  T use<T>(Coil<T> coil) {
    switch (_elements[coil._key]) {
      case final _CoilElement<_MutableCoilState<T>> element?:
        _owner?._dependOn(element);
        return element.state.value;
      case final _CoilElement<T> element?:
        _owner?._dependOn(element);
        return element.state;
      case _:
        final T state;
        final _CoilElement element;
        switch (coil) {
          case _MutableValueCoil<T>():
            final stateFactory = coil.createStateFactory();
            element = _CoilElement<_MutableCoilState<T>>(this, coil);
            element.state = stateFactory(_clone(element));
            state = element.state.value;
          case _:
            element = _CoilElement<T>(this, coil);
            element.state = coil._factory(_clone(element));
            state = element.state;
        }
        _elements[coil._key] = element;
        _owner?._dependOn(element);

        return state;
    }
  }

  @override
  void mutate<T>(MutableCoil<T> coil, T Function(T p1) updater) {
    switch (_elements[coil._key]) {
      case final _CoilElement<_MutableCoilState<T>> element?:
        element.state.value = updater(element.state.value);
      case _:
        return;
    }
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    switch (_elements[coil._key]) {
      case final _?:
        _elements.remove(coil._key);
      case _:
        return;
    }
  }

  Scope _clone(_CoilElement owner) => Scope._(owner: owner, bucket: {..._elements});
}

Coil<T> coil<T>(RefFactory<T> factory, {String? debugName}) => _ValueCoil<T>(factory, debugName: debugName);

MutableCoil<T> mutableCoil<T>(RefFactory<T> factory, {String? debugName}) =>
    _MutableValueCoil<T>(factory, debugName: debugName);

@optionalTypeArgs
class _CoilElement<T> {
  _CoilElement(this._scope, this._coil);

  final Scope _scope;
  final Coil _coil;

  final Set<_CoilElement> _dependents = {};

  T get state {
    assert(_state != null, 'Should set the state');
    return _state!;
  }

  T? _state;

  set state(T value) {
    if (_state != value) {
      _state = value;
      _invalidateDependents();
    }
  }

  void invalidate() {
    _invalidateDependents();
    _scope._elements.remove(_coil._key);
    _dependents.clear();
  }

  void _dependOn(_CoilElement element) => element._dependents.add(this);

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

class _ValueCoil<T> extends Coil<T> {
  _ValueCoil(super._factory, {super.debugName});
}

class _MutableValueCoil<T> extends Coil<T> with MutableCoil<T> {
  _MutableValueCoil(super._factory, {super.debugName});

  _MutableCoilState<T> Function(Scope scope) createStateFactory() => (Scope scope) => _MutableCoilState(
        () => _factory(scope),
        () => scope._owner?._invalidateDependents(),
      );
}

class _MutableCoilState<T> {
  _MutableCoilState(this._factory, this._onUpdate);

  final T Function() _factory;
  final void Function() _onUpdate;

  T get value => _value;
  late T _value = _factory();

  set value(T value) {
    if (value != _value) {
      _value = value;
      _onUpdate();
    }
  }

  @override
  String toString() => 'CoilState($_value)';
}
