import 'package:meta/meta.dart';

abstract class Ref {
  T use<T>(Coil<T> coil);

  void mutate<T>(MutableCoil<T> coil, T Function(T) updater);

  void invalidate<T>(Coil<T> coil);
}

typedef RefFactory<T> = T Function(Ref);

sealed class Coil<T> {
  RefFactory<T> get _factory;

  late final int _key = identityHashCode(this);
}

mixin MutableCoil<T> on Coil<T> {}

class Scope implements Ref {
  Scope() : _bucket = {};

  final Map<int, _CoilElement> _bucket;

  @override
  T use<T>(Coil<T> coil) {
    switch (_bucket[coil._key]) {
      case final _CoilElement<_MutableCoilState<T>> element?:
        return element.state.value;
      case final _CoilElement<T> element?:
        return element.state;
      case _:
        final T state;
        final _CoilElement element;
        switch (coil) {
          case _MutableValueCoil<T>():
            final coilState = coil.createState(this);
            state = coilState.value;
            element = _CoilElement<_MutableCoilState<T>>(coilState);
          case _:
            state = coil._factory(this);
            element = _CoilElement<T>(state);
        }
        _bucket[coil._key] = element;

        return state;
    }
  }

  @override
  void mutate<T>(MutableCoil<T> coil, T Function(T p1) updater) {
    switch (_bucket[coil._key]) {
      case final _CoilElement<_MutableCoilState<T>> element?:
        element.state.value = updater(element.state.value);
      case _:
        return;
    }
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    switch (_bucket[coil._key]) {
      case final _?:
        _bucket.remove(coil._key);
      case _:
        return;
    }
  }
}

Coil<T> coil<T>(RefFactory<T> factory) => _ValueCoil(factory);

MutableCoil<T> mutableCoil<T>(RefFactory<T> factory) => _MutableValueCoil(factory);

@optionalTypeArgs
class _CoilElement<T> {
  _CoilElement(this._state);

  T get state => _state;
  T _state;

  set state(T value) {
    _state = value;
  }
}

class _ValueCoil<T> extends Coil<T> {
  _ValueCoil(this._factory);

  @override
  final RefFactory<T> _factory;
}

class _MutableValueCoil<T> extends _ValueCoil<T> with MutableCoil<T> {
  _MutableValueCoil(super._factory);

  _MutableCoilState<T> createState(Ref ref) => _MutableCoilState(
        () => _factory(ref),
        (_) => _,
      );
}

class _MutableCoilState<T> {
  _MutableCoilState(this._factory, this._onUpdate);

  final T Function() _factory;
  final T Function(T) _onUpdate;

  T get value => _value;
  late T _value = _factory();

  set value(T value) {
    if (value != _value) {
      _value = value;
      _onUpdate(value);
    }
  }
}
