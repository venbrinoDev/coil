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

  final Map<int, Object> _bucket;

  @override
  T use<T>(Coil<T> coil) {
    switch (_bucket[coil._key]) {
      case final _MutableCoilState<T> coilState?:
        return coilState.value;
      case final T state?:
        return state;
      case _:
        final T state;
        switch (coil) {
          case _MutableValueCoil<T>():
            final coilState = coil.createState(this);
            state = coilState.value;
            _bucket[coil._key] = coilState;
          case _:
            state = coil._factory(this);
            _bucket[coil._key] = state as Object;
        }

        return state;
    }
  }

  @override
  void mutate<T>(MutableCoil<T> coil, T Function(T p1) updater) {
    switch (_bucket[coil._key]) {
      case final _MutableCoilState<T> coilState?:
        coilState.value = updater(coilState.value);
        _bucket[coil._key] = coilState;
      case _:
        return;
    }
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    // TODO: implement invalidate
  }
}

Coil<T> coil<T>(RefFactory<T> factory) => _ValueCoil(factory);

MutableCoil<T> mutableCoil<T>(RefFactory<T> factory) => _MutableValueCoil(factory);

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
