abstract class Ref {
  T use<T>(Coil<T> coil);

  void mutate<T>(Coil<T> coil, T Function(T) updater);

  void invalidate<T>(Coil<T> coil);
}

typedef RefFactory<T> = T Function(Ref);

abstract class Coil<T> {
  RefFactory<T> get _factory;

  late final int _key = identityHashCode(this);
}

class Scope implements Ref {
  Scope() : _bucket = {};

  final Map<int, Object> _bucket;

  @override
  T use<T>(Coil<T> coil) {
    switch (_bucket[coil._key]) {
      case final T state?:
        return state;
      case _:
        final state = coil._factory(this);
        _bucket[coil._key] = state as Object;
        return state;
    }
  }

  @override
  void mutate<T>(Coil<T> coil, T Function(T p1) updater) {
    // TODO: implement mutate
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    // TODO: implement invalidate
  }
}

Coil<T> coil<T>(RefFactory<T> factory) {
  return _ValueCoil(factory);
}

class _ValueCoil<T> extends Coil<T> {
  _ValueCoil(this._factory);

  @override
  final RefFactory<T> _factory;
}
