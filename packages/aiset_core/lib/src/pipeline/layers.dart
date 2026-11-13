part of 'pipeline.dart';

/// The mounted data layers of a configuration
/// (`SPEC.md` amendment 7).
///
/// A layer is a stored document a named owner contributes at a
/// document coordinate. The host defines the list and its order;
/// the library imposes no universal policy. Two rules bind the
/// merge:
///
/// * the document below wins every conflict, which is what makes a
///   plugin's defaults unable to overwrite a user's setting
///   (`SPEC.md` amendment 7: base-preferred merge), and
/// * a layer's values are never materialized into the
///   document's source. They appear in the effective view, and
///   editing an inherited value creates an override in the main
///   document (`SPEC.md` amendment 7).
///
/// The provenance map this produces names the owning layer for each
/// pointer a layer supplied, so the effective view reports
/// where an inherited value came from instead of pretending the document
/// held it (`SPEC.md` amendment 6). A
/// placeholder is never resolved by a layer,
/// and the layer's text is read as stored data.
/// The result of placing the [layers] over one stored tree.
final class LayeredView {
  /// Creates a layered view.
  LayeredView({required this.tree, required this.provenance});

  /// The merged tree: the document's own values with the layers
  /// filling the gaps.
  final Object? tree;

  /// The pointers a layer supplied, with the owning layer named.
  final Map<String, Provenance> provenance;
}

/// Merges [layers] over [stored], highest precedence first.
LayeredView applyMountLayers(Object? stored, List<MountLayer> layers) {
  var tree = stored;
  final provenance = <String, Provenance>{};
  for (final layer in layers) {
    final Object? contribution;
    try {
      contribution = Json5Document(layer.source, origin: layer.owner).storedValue();
    } on Json5SourceException {
      // An unreadable layer contributes nothing. The host learns about it
      // from the audit record rather than by losing its own document.
      continue;
    }
    tree = layer.target.isEmpty
        ? _layeredMerge(tree, contribution, layer.owner, '', provenance)
        : _placeLayer(tree, parsePointer(layer.target), contribution, layer, provenance);
  }
  return LayeredView(tree: tree, provenance: provenance);
}

/// Merges [update] into the copy of [tree] addressed by [tokens], creating
/// absent containers along the way.
///
/// A mount into a scalar or past the end of an array
/// places nothing: a layer may fill a gap, it may not
/// overwrite a value the document holds (`SPEC.md`
/// amendment 7, the free-space check).
Object? _placeLayer(Object? tree, List<String> tokens, Object? update, MountLayer layer,
    Map<String, Provenance> provenance) {
  if (tokens.isEmpty) {
    return _layeredMerge(tree, update, layer.owner, layer.target, provenance);
  }
  final token = tokens.first;
  if (isObjectValue(tree)) {
    final map = (tree! as Map<Object?, Object?>).cast<Object?, Object?>();
    final result = <String, Object?>{
      for (final entry in map.entries) entry.key! as String: mutableCopy(entry.value),
    };
    final present = mapHas(map, token);
    result[token] = present
        ? _placeLayer(map[token], tokens.skip(1).toList(), update, layer, provenance)
        : _createdLayerValue(tokens, update, layer, provenance);
    return result;
  }
  if (tree is List) {
    final index = indexValue(token);
    if (!isIndexToken(token) || index == null || index >= tree.length) return tree;
    final items = [for (final item in tree) mutableCopy(item)];
    items[index] = _placeLayer(items[index], tokens.skip(1).toList(), update, layer, provenance);
    return items;
  }
  return tree;
}

/// The value of a mount path the document does not have yet: the whole
/// contribution, with provenance on every pointer inside it.
Object? _createdLayerValue(List<String> tokens, Object? update, MountLayer layer,
    Map<String, Provenance> provenance) {
  var value = update;
  for (final token in tokens.skip(1).toList().reversed) {
    value = <String, Object?>{token: value};
  }
  _recordLayer(layer.target, value, layer.owner, provenance);
  return mutableCopy(value);
}

/// Merges a layer object into the document object at one coordinate.
Object? _layeredMerge(
  Object? base,
  Object? update,
  String owner,
  String path,
  Map<String, Provenance> provenance,
) {
  if (!isObjectValue(base) || !isObjectValue(update)) {
    // Only an object can be layered at a coordinate; anything else
    // contributes nothing rather than replacing what the document says.
    return base;
  }
  final merged = merge(base, update);
  final left = (base! as Map<Object?, Object?>).cast<Object?, Object?>();
  final right = (update as Map<Object?, Object?>).cast<Object?, Object?>();
  for (final entry in right.entries) {
    final key = entry.key! as String;
    if (mapHas(left, key)) continue;
    final childPath = '$path/${escapeToken(key)}';
    provenance.putIfAbsent(childPath, () => Provenance(kind: ProvenanceKind.layer, layer: owner));
    for (final inner in _innerPointerPaths(entry.value)) {
      provenance.putIfAbsent('$childPath$inner',
          () => Provenance(kind: ProvenanceKind.layer, layer: owner));
    }
  }
  return merged;
}

/// Records [owner] as the source of [value]'s whole subtree under [path].
void _recordLayer(
    String path, Object? value, String owner, Map<String, Provenance> provenance) {
  provenance.putIfAbsent(path, () => Provenance(kind: ProvenanceKind.layer, layer: owner));
  for (final inner in _innerPointerPaths(value)) {
    provenance.putIfAbsent('$path$inner',
        () => Provenance(kind: ProvenanceKind.layer, layer: owner));
  }
}

/// Every pointer inside [value], the value itself excluded.
List<String> _innerPointerPaths(Object? value) {
  final out = <String>[];
  void walk(Object? node, String path) {
    if (isObjectValue(node)) {
      final map = (node! as Map<Object?, Object?>).cast<Object?, Object?>();
      for (final entry in map.entries) {
        final child = '$path/${escapeToken(entry.key! as String)}';
        out.add(child);
        walk(entry.value, child);
      }
    } else if (node is List) {
      for (var index = 0; index < node.length; index++) {
        final child = '$path/$index';
        out.add(child);
        walk(node[index], child);
      }
    }
  }

  walk(value, '');
  return out;
}
