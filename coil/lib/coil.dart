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

  U mutateSelf(CoilMutation<U?> updater);

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

  @override
  T get<T>(Coil<T> coil, {bool listen = true}) {
    switch (_elements[coil]) {
      case CoilElement<T> element:
        return element.state;
      case _:
        final element = coil.createElement();
        _elements[coil] = element;

        final state = coil.factory(Scope._(element, this));
        element.state = state;

        return state;
    }
  }

  @override
  T mutate<T>(Coil<T> coil, CoilMutation<T> updater) {
    throw UnimplementedError();
  }

  @override
  @protected
  @Deprecated('???')
  U mutateSelf(CoilMutation<U?> updater) {
    throw UnimplementedError();
  }

  @override
  CoilSubscription<T> listen<T>(
    Coil<T> coil,
    CoilListener<T> listener, {
    bool fireImmediately = false,
  }) {
    throw UnimplementedError();
  }

  @override
  void invalidate<T>(Coil<T> coil) {
    throw UnimplementedError();
  }

  @override
  void onDispose(VoidCallback callback) {
    // TODO: Unimplemented
  }

  void dispose() {
    // TODO: Unimplemented
  }
}

@optionalTypeArgs
class CoilElement<T> {
  CoilElement(this._coil);

  final Coil<T> _coil;

  T get state {
    assert(_state != null, 'Needs to have its state set at least once');
    return _state!;
  }

  T? _state;

  set state(T value) {
    _state = value;
  }

  @override
  String toString() {
    if (_coil.debugName case final debugName?) {
      return 'CoilElement($debugName)';
    }

    return runtimeType.toString();
  }
}
