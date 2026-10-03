import 'dart:collection';

import '../prop_source.dart';

/// Concatenates source snapshots without repeatedly copying long merge chains.
/// Small properties keep using ordinary lists to avoid tree overhead.
List<PropSource<V>> concatPropSources<V>(
  List<PropSource<V>> current,
  List<PropSource<V>> other,
) {
  if (current.length + other.length <= 32) {
    return [...current, ...other];
  }

  return _MergedSources(_SourceConcat(_snapshot(current), _snapshot(other)));
}

_SourceNode<V> _snapshot<V>(List<PropSource<V>> sources) {
  if (sources is _MergedSources<V>) return sources.snapshot();

  // Ordinary lists are publicly mutable, so capture their current contents.
  return _SourceChunk(List.of(sources));
}

sealed class _SourceNode<V> {
  int get length;
}

final class _SourceChunk<V> extends _SourceNode<V> {
  final List<PropSource<V>> values;

  _SourceChunk(this.values);

  @override
  int get length => values.length;
}

final class _SourceConcat<V> extends _SourceNode<V> {
  final _SourceNode<V> left;
  final _SourceNode<V> right;

  @override
  final int length;

  _SourceConcat(this.left, this.right) : length = left.length + right.length;
}

/// A growable list facade over an immutable concatenation tree.
/// Reads flatten once; writes detach from snapshots captured by later merges.
final class _MergedSources<V> extends ListBase<PropSource<V>> {
  _SourceNode<V> _root;
  List<PropSource<V>>? _values;
  bool _shared = false;

  _MergedSources(this._root);

  _SourceNode<V> snapshot() {
    final values = _values;
    if (values != null) {
      _root = _SourceChunk(values);
      _shared = true;
    }

    return _root;
  }

  List<PropSource<V>> _materialize() {
    final existing = _values;
    if (existing != null) return existing;

    final values = <PropSource<V>>[];
    final pending = <_SourceNode<V>>[_root];
    // Iterative traversal also handles deeply skewed merge chains without
    // consuming one stack frame per merge.
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case _SourceChunk<V>(values: final chunk):
          values.addAll(chunk);
        case _SourceConcat<V>(:final left, :final right):
          pending
            ..add(right)
            ..add(left);
      }
    }
    _values = values;
    _root = _SourceChunk(values);

    return values;
  }

  List<PropSource<V>> get _writable {
    final values = _materialize();
    if (!_shared) return values;

    _shared = false;
    final detached = List<PropSource<V>>.of(values);
    _values = detached;
    _root = _SourceChunk(detached);

    return detached;
  }

  @override
  int get length => _values?.length ?? _root.length;

  @override
  set length(int value) => _writable.length = value;

  @override
  PropSource<V> operator [](int index) => _materialize()[index];

  @override
  void operator []=(int index, PropSource<V> value) {
    _writable[index] = value;
  }

  @override
  void add(PropSource<V> value) => _writable.add(value);

  @override
  void addAll(Iterable<PropSource<V>> iterable) {
    final values = _writable;
    values.addAll(identical(iterable, this) ? values : iterable);
  }

  @override
  void insert(int index, PropSource<V> element) =>
      _writable.insert(index, element);

  @override
  void insertAll(int index, Iterable<PropSource<V>> iterable) {
    final values = _writable;
    values.insertAll(index, identical(iterable, this) ? values : iterable);
  }

  @override
  void replaceRange(int start, int end, Iterable<PropSource<V>> replacements) {
    final values = _writable;
    values.replaceRange(
      start,
      end,
      identical(replacements, this) ? values : replacements,
    );
  }
}
