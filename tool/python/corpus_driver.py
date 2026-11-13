#!/usr/bin/env python3
"""Execute the Python behavioral baseline over a corpus job.

This is the oracle half of ``tool/generate_corpus.dart``: it reads a JSON
job on stdin, runs each case against ``aiset.jsonsrc`` (the baseline
library, imported with ``PYTHONPATH`` pointed at the reference
clone's ``src``), and writes one JSON result object to stdout.

It is a generator adapter, not project runtime code: nothing here is
copied into the Dart library (SPEC.md amendment 24), and it must not
modify the reference clone. Run with ``PYTHONDONTWRITEBYTECODE=1`` and
without a pytest cache so the clone stays pristine.

Job schema (stdin)::

    {
      "cases": [
        {"id": str, "kind": "parse", "input": str},
        {"id": str, "kind": "query", "input": str,
         "query": {"op": "stored_value"|"value_text"|"format_of"|"paths",
                   "pointer": str}},
        {"id": str, "kind": "operation", "input": str,
         "operation": {"op": "set", "pointer": str, "value_text": str}
                    | {"op": "add", "pointer": str, "value_text": str}
                    | {"op": "remove", "pointer": str}
                    | {"op": "move", "source": str, "target": str}
                    | {"op": "rename", "pointer": str, "new_key": str}},
        {"id": str, "kind": "descriptor_validate", "input": str,
         "mode": "default"|"strict"},
        {"id": str, "kind": "descriptor_compile", "input": str,
         "strict": bool, "typedefSources": [str, ...],
         "fragments": [{"source": str, "mount": str}, ...]},
        {"id": str, "kind": "descriptor_query", "input": str, "strict": bool,
         "typedefSources": [str, ...],
         "query": {"op": "node_at"|"has_node"|"revision", "pointer": str}
                  | {"op": "node_field", "pointer": str, "field": str},
         "fragments": [{"source": str, "mount": str}, ...]}
      ],
      "hash_files": [str, ...]   # files whose bytes the generator identifies
    }

Result schema (stdout)::

    {"results": [ {...one object per case, see _run_case...} ],
     "generator_sha256": str}

Every expectation in the result is produced by executing the baseline,
never transcribed by hand.
"""

from __future__ import annotations

import copy
import hashlib
import json
import math
import sys
from pathlib import Path

from aiset.errors import AisetError
from aiset.jsonsrc import Document, TemplateRef
from aiset.resolver import MISSING, Resolver, build_effective, effective_at, is_missing


def encode_value(value: object) -> dict:
    """Tagged, deterministic JSON encoding of a baseline stored value.

    Python ``int`` is unbounded and ``float`` may be
    non-finite, neither of which JSON represents directly, so every
    scalar carries an explicit kind tag. Object entries are kept as
    a list of pairs to preserve insertion order.
    """
    if value is None:
        return {"k": "null"}
    if is_missing(value):
        return {"k": "missing"}
    if isinstance(value, bool):
        return {"k": "bool", "v": value}
    if isinstance(value, int):
        return {"k": "int", "v": str(value)}
    if isinstance(value, float):
        if math.isfinite(value):
            return {"k": "double", "v": value}
        special = "nan" if math.isnan(value) else ("inf" if value > 0 else "-inf")
        return {"k": "double", "v": special}
    if isinstance(value, str):
        return {"k": "string", "v": value}
    if isinstance(value, TemplateRef):
        return {"k": "template", "v": {"name": value.name, "default": value.default}}
    if isinstance(value, dict):
        return {"k": "object", "v": [[key, encode_value(item)] for key, item in value.items()]}
    if isinstance(value, list):
        return {"k": "array", "v": [encode_value(item) for item in value]}
    raise TypeError(f"unencodable baseline value: {type(value).__name__}")


def describe_error(exc: BaseException) -> dict:
    """Stable code plus class name of a baseline failure.

    A non-``AisetError`` crash (e.g. ``IndexError`` on truncated input) has
    no stable code; it is recorded as a crash so the corpus pins only the
    accept/reject outcome for it (SPEC.md amendments 30 and 32, tier 3).
    """
    code = exc.code if isinstance(exc, AisetError) else None
    return {
        "errorCode": code,
        "errorClass": type(exc).__name__,
        "baselineCrash": not isinstance(exc, AisetError),
    }


def run_parse(case: dict) -> dict:
    text = case["input"]
    try:
        document = Document(text)
    except Exception as exc:  # noqa: BLE001 - the oracle outcome is what we pin
        return {
            "id": case["id"],
            "area": "parse_reject",
            "accepted": False,
            **describe_error(exc),
        }
    return {
        "id": case["id"],
        "area": "parse_accept",
        "accepted": True,
        "rootText": document.source_of(document.root),
        "storedValue": encode_value(document.stored_value(document.root)),
        "formatOf": document.format_of(document.root),
        "paths": document.paths(""),
    }


def run_query(case: dict) -> dict:
    query = case["query"]
    pointer = query["pointer"]
    operation = query["op"]
    try:
        document = Document(case["input"])
        node = document.find(pointer)
        if operation == "stored_value":
            outcome = {"ok": True, "result": encode_value(document.stored_value(node))}
        elif operation == "value_text":
            outcome = {"ok": True, "result": document.value_text(node)}
        elif operation == "format_of":
            outcome = {"ok": True, "result": document.format_of(node)}
        elif operation == "paths":
            outcome = {"ok": True, "result": document.paths(pointer)}
        else:
            raise ValueError(f"unknown query op {operation!r}")
    except Exception as exc:  # noqa: BLE001
        outcome = {"ok": False, **describe_error(exc)}
    return {"id": case["id"], "area": "values", "query": query, **outcome}


def run_operation(case: dict) -> dict:
    operation = case["operation"]
    kind = operation["op"]

    def invoke() -> str:
        document = Document(case["input"])
        if kind == "set":
            return document.apply_set(operation["pointer"], operation["value_text"])
        if kind == "add":
            return document.apply_add(operation["pointer"], operation["value_text"])
        if kind == "remove":
            return document.apply_remove(operation["pointer"])
        if kind == "move":
            return document.apply_move(operation["source"], operation["target"])
        if kind == "rename":
            return document.apply_rename(operation["pointer"], operation["new_key"])
        raise ValueError(f"unknown operation {kind!r}")

    try:
        output = invoke()
    except Exception as exc:  # noqa: BLE001
        return {"id": case["id"], "area": "operations", "ok": False, **describe_error(exc)}
    result: dict = {"id": case["id"], "area": "operations", "ok": True, "output": output}
    # Reparsing the produced text is part of the observable contract:
    # an edit must leave a document the engine still accepts.
    try:
        reparsed = Document(output)
    except Exception as exc:  # noqa: BLE001
        result["reparse"] = {"ok": False, **describe_error(exc)}
    else:
        result["reparse"] = {
            "ok": True,
            "storedValue": encode_value(reparsed.stored_value(reparsed.root)),
            "paths": reparsed.paths(""),
        }
    return result


# ---------------------------------------------------------------------------
# descriptor grammar
# ---------------------------------------------------------------------------


def encode_issue(issue: dict) -> dict:
    """One descriptor diagnostic, without its message text.

    The message is tier-3 presentation and may echo the author's file, so the
    corpus pins the stable code, the severity, the pointer the diagnostic points
    at, and the source position. ``hasMessage`` records only that a message
    was produced.
    """
    out = {
        "code": issue["code"],
        "severity": issue["severity"],
        "path": issue["path"],
        "hasMessage": bool(issue.get("message")),
    }
    for key in ("line", "column"):
        if issue.get(key) is not None:
            out[key] = issue[key]
    return out


def encode_node(node: object) -> dict:
    """The full observable meaning of one compiled descriptor node.

    Every field the compiler exposes is emitted, including the ones
    that are absent, so a comparison cannot pass by omitting a
    constraint. Values that hold arbitrary JSON use the tagged encoding above.
    """
    raw = getattr(node, "raw", None) or {}
    return {
        "type": node.type,
        "path": node.path,
        "label": node.label,
        "fieldName": node.field_name,
        "typedefName": node.typedef_name,
        "description": node.description,
        "title": node.title,
        "required": node.required,
        "nullable": node.nullable,
        "hasDefault": node.has_default,
        "hasConst": "const" in raw,
        "default": encode_value(node.default),
        "enum": None if node.enum is None else [encode_value(v) for v in node.enum],
        "const": encode_value(node.const) if "const" in raw else None,
        "minimum": encode_value(node.minimum),
        "maximum": encode_value(node.maximum),
        "minLength": encode_value(node.min_length),
        "maxLength": encode_value(node.max_length),
        "pattern": node.pattern,
        "minItems": encode_value(node.min_items),
        "maxItems": encode_value(node.max_items),
        "uniqueItems": node.unique_items,
        "keyPattern": node.key_pattern,
        "keyEnum": None if node.key_enum is None else list(node.key_enum),
        "envAllowed": node.env_allowed,
        "envConvert": node.env_convert,
        "secret": node.secret,
        "readOnly": node.read_only,
        "apply": node.apply,
        "validators": list(node.validators or []),
        "ui": None if node.ui is None else encode_value(dict(node.ui)),
        "helper": None if node.helper is None else encode_value(dict(node.helper)),
        "hooks": None if node.hooks is None else encode_value(dict(node.hooks)),
        "children": (
            None
            if not node.children
            else [
                [name, child.label, encode_node(child)]
                for name, child in node.children.items()
            ]
        ),
        "additionalChildren": (
            None if node.additional_children is None else encode_node(node.additional_children)
        ),
        "itemNode": None if node.item_node is None else encode_node(node.item_node),
        "optionNodes": (
            None if node.option_nodes is None else [encode_node(o) for o in node.option_nodes]
        ),
    }


def run_descriptor_validate(case: dict) -> dict:
    from aiset.descriptor import validate_descriptor

    try:
        diagnostic = validate_descriptor(case["input"], mode=case.get("mode", "default"))
    except Exception as exc:  # noqa: BLE001
        return {"id": case["id"], "area": "descriptor_validate", "ok": False, **describe_error(exc)}
    return {
        "id": case["id"],
        "area": "descriptor_validate",
        "ok": True,
        "valid": diagnostic.valid,
        "issues": [encode_issue(issue.to_dict()) for issue in diagnostic.issues],
    }


def run_descriptor_compile(case: dict) -> dict:
    from aiset.descriptor import DescriptorFragment, compile_descriptor
    from aiset.errors import InvalidDescriptor

    fragments = [
        DescriptorFragment(source=item["source"], mount=item["mount"])
        for item in case.get("fragments", [])
    ]
    try:
        compiled = compile_descriptor(
            case["input"],
            typedef_sources=list(case.get("typedefSources", [])),
            fragments=fragments,
            strict=bool(case.get("strict", False)),
        )
    except InvalidDescriptor as exc:
        return {
            "id": case["id"],
            "area": "descriptor_compile",
            "ok": False,
            "errorCode": exc.code,
            "errorClass": type(exc).__name__,
            "baselineCrash": False,
            "issues": [encode_issue(issue) for issue in exc.issues],
        }
    except Exception as exc:  # noqa: BLE001
        return {"id": case["id"], "area": "descriptor_compile", "ok": False, **describe_error(exc)}
    return {
        "id": case["id"],
        "area": "descriptor_compile",
        "ok": True,
        "revision": compiled.revision,
        "project": compiled.project,
        "configVersion": compiled.config_version,
        "shape": encode_node(compiled.root),
    }


# Query field name -> the compiled node attribute it reads.
NODE_FIELD_ATTRIBUTES = {
    "type": "type",
    "label": "label",
    "fieldName": "field_name",
    "typedefName": "typedef_name",
    "description": "description",
    "title": "title",
    "required": "required",
    "nullable": "nullable",
    "hasDefault": "has_default",
    "default": "default",
    "enum": "enum",
    "const": "const",
    "minimum": "minimum",
    "maximum": "maximum",
    "minLength": "min_length",
    "maxLength": "max_length",
    "pattern": "pattern",
    "minItems": "min_items",
    "maxItems": "max_items",
    "uniqueItems": "unique_items",
    "keyPattern": "key_pattern",
    "keyEnum": "key_enum",
    "envAllowed": "env_allowed",
    "envConvert": "env_convert",
    "secret": "secret",
    "readOnly": "read_only",
    "apply": "apply",
    "validators": "validators",
    "ui": "ui",
    "helper": "helper",
    "hooks": "hooks",
}


def run_descriptor_query(case: dict) -> dict:
    from aiset.descriptor import DescriptorFragment, compile_descriptor, node_at

    query = case["query"]
    try:
        compiled = compile_descriptor(
            case["input"],
            typedef_sources=list(case.get("typedefSources", [])),
            fragments=[
                DescriptorFragment(source=item["source"], mount=item["mount"])
                for item in case.get("fragments", [])
            ],
            strict=bool(case.get("strict", False)),
        )
        if query["op"] == "has_node":
            payload: object = node_at(compiled, query["pointer"]) is not None
        elif query["op"] == "node_field":
            found = node_at(compiled, query["pointer"])
            if found is None:
                raise ValueError(f"no node at {query['pointer']!r}")
            attribute = NODE_FIELD_ATTRIBUTES.get(query["field"])
            if attribute is None:
                raise ValueError(f"unknown node field {query['field']!r}")
            payload = encode_value(getattr(found, attribute))
        elif query["op"] == "node_at":
            found = node_at(compiled, query["pointer"])
            payload = None if found is None else {"node": encode_node(found)}
        elif query["op"] == "revision":
            payload = compiled.revision
        else:
            raise ValueError(f"unknown descriptor query {query['op']!r}")
    except Exception as exc:  # noqa: BLE001
        return {
            "id": case["id"],
            "area": "descriptor_semantics",
            "query": query,
            "ok": False,
            **describe_error(exc),
        }
    return {
        "id": case["id"],
        "area": "descriptor_semantics",
        "query": query,
        "ok": True,
        "result": payload,
    }


# ---------------------------------------------------------------------------
# resolver
# ---------------------------------------------------------------------------


def make_resolver(case: dict) -> Resolver:
    """A resolver over only the layers the case names.

    Every layer is passed explicitly: the baseline's own default for
    ``environ`` is the process environment, and a corpus that read it would
    depend on the machine it ran on.
    """
    layers = case.get("layers", {})
    return Resolver(
        overrides=dict(layers.get("overrides", {})),
        dotenv=dict(layers.get("dotenv", {})),
        environ=dict(layers.get("environ", {})),
    )


def encode_issues(issues: list) -> list:
    """The observable part of a resolver issue: rule, path, severity."""
    return [
        {"rule": issue.rule, "path": issue.path, "severity": issue.severity,
         "hasMessage": bool(issue.message)}
        for issue in issues
    ]


def run_resolver_lookup(case: dict) -> dict:
    resolver = make_resolver(case)
    query = case["query"]
    if query["op"] == "lookup":
        value, source = resolver.lookup(query["name"], query.get("inlineDefault"))
        result = {"value": value, "source": source}
    elif query["op"] == "presence":
        result = {"presence": resolver.presence(query["names"])}
    else:
        raise ValueError(f"unknown resolver lookup op {query['op']!r}")
    return {"id": case["id"], "area": "resolver_lookup", "query": query,
            "ok": True, "result": encode_value(result)}


def run_resolver_text(case: dict) -> dict:
    resolver = make_resolver(case)
    issues: list = []
    provenance: dict = {}
    path = case.get("path", "/value")
    try:
        output = resolver.resolve_text(case["input"], path, issues, provenance)
    except Exception as exc:  # noqa: BLE001
        return {"id": case["id"], "area": "resolver_text", "ok": False, **describe_error(exc)}
    return {
        "id": case["id"],
        "area": "resolver_text",
        "ok": True,
        "output": output,
        "issues": encode_issues(issues),
        "provenance": encode_value(provenance),
    }


def run_resolver_effective(case: dict) -> dict:
    from aiset.descriptor import compile_descriptor, node_at

    layers = case.get("layers", {})
    before = copy.deepcopy(layers)
    try:
        descriptor = compile_descriptor(case["descriptor"], strict=True)
        document = Document(case["config"])
        stored = document.stored_value(document.root)
        stored_before = copy.deepcopy(stored)
        resolver = make_resolver(case)
        provenance: dict = {}
        query = case.get("query")
        if query and query["op"] == "effective_at":
            raw = query.get("stored")
            node = node_at(descriptor, query["pointer"])
            value = MISSING if raw == "MISSING" else raw
            effective, issues = effective_at(
                value, node, resolver, query.get("path", ""), provenance=provenance
            )
        else:
            effective, issues = build_effective(
                stored, descriptor.root, resolver, provenance=provenance
            )
    except Exception as exc:  # noqa: BLE001
        return {"id": case["id"], "area": "resolver_effective", "ok": False, **describe_error(exc)}
    result = {
        "id": case["id"],
        "area": "resolver_effective",
        "ok": True,
        "effective": encode_value(effective),
        "issues": encode_issues(issues),
        "provenance": encode_value(provenance),
    }
    # Resolution must not mutate its inputs: neither the stored tree it was
    # handed nor the value maps the host supplied.
    result["inputsUnchanged"] = (
        stored == stored_before
        and layers == before
        and dict(resolver.overrides) == before.get("overrides", {})
        and dict(resolver.environ) == before.get("environ", {})
        and dict(resolver.dotenv) == before.get("dotenv", {})
    )
    return result


# ---------------------------------------------------------------------------
# validator
# ---------------------------------------------------------------------------


def encode_value_issue(issue) -> dict:
    """The observable part of a validation issue.

    The message is tier-3 presentation; the corpus pins the rule,
    the pointer and the severity.
    """
    return {
        "rule": issue.rule,
        "path": issue.path,
        "severity": issue.severity,
        "hasMessage": bool(issue.message),
    }


def make_limits(case: dict):
    from aiset.validator import Limits

    overrides = case.get("limits") or {}
    return Limits(**overrides)


def run_validator_profile(case: dict) -> dict:
    from dataclasses import asdict, fields
    from aiset.validator import DEFAULT_LIMITS, Limits

    defaults = {f.name: getattr(Limits(), f.name) for f in fields(Limits)}
    assert asdict(DEFAULT_LIMITS) == defaults
    return {"id": case["id"], "area": "validator_profile", "ok": True,
            "limits": defaults}


def decode_fixture_value(tagged: object) -> object:
    """Turn a fixture value tag into the baseline data object.

    Plain JSON scalars, lists and maps pass through; the explicit
    sentinels the corpus needs are ``{"missing": true}`` and
    ``{"template": {"name": …, "default": …|null}}``.
    """
    if isinstance(tagged, dict):
        if tagged.get("missing") is True:
            from aiset.resolver import MISSING

            return MISSING
        template = tagged.get("template")
        if isinstance(template, dict):
            return TemplateRef(template["name"], template.get("default"))
        return {key: decode_fixture_value(item) for key, item in tagged.items()}
    if isinstance(tagged, list):
        return [decode_fixture_value(item) for item in tagged]
    return tagged


def run_validator_value(case: dict) -> dict:
    from aiset.descriptor import compile_descriptor, node_at
    from aiset.validator import validate_document, validate_value, ValidationContext

    area = case.get("area", "validator_value")
    stored = None
    try:
        descriptor = compile_descriptor(case["descriptor"], strict=True)
        if case.get("direct"):
            query = case["query"]
            stored = decode_fixture_value(query["value"])
            pointer = query.get("pointer")
            node = None if pointer is None else node_at(descriptor, pointer)
            issues = validate_value(
                stored,
                node,
                query.get("path", ""),
                ValidationContext(limits=make_limits(case)),
                present=bool(query.get("present", True)),
            )
        else:
            document = Document(case["value"])
            stored = document.stored_value(document.root)
            issues = validate_document(stored, descriptor.root, limits=make_limits(case))
    except Exception as exc:  # noqa: BLE001
        return {"id": case["id"], "area": area, "ok": False, **describe_error(exc)}
    result = {
        "id": case["id"],
        "area": area,
        "ok": True,
        "valid": not [i for i in issues if i.severity == "error"],
        "issues": [encode_value_issue(i) for i in issues],
    }
    if not case.get("direct"):
        # Validation reads its inputs and never writes to them.
        result["inputsUnchanged"] = document.stored_value(document.root) == stored
    return result


# ---------------------------------------------------------------------------
# merge (SPEC.md amendment 7)
# ---------------------------------------------------------------------------


def decode_plain(value: object) -> object:
    """Turn a fixture value tag into the baseline's own data tree.

    The tagged encoding pins the value *kind* — Python
    `1`, `True` and `1.0` are three different stored values and the
    merge treats them differently — so a merge case carries the same
    `{"k": …}` encoding every other area uses, decoded here.
    """
    if not isinstance(value, dict):
        return value
    kind = value.get("k")
    if kind == "null":
        return None
    if kind == "bool":
        return bool(value["v"])
    if kind == "int":
        return int(value["v"])
    if kind == "double":
        return float(value["v"])
    if kind == "string":
        return value["v"]
    if kind == "template":
        return TemplateRef(value["v"]["name"], value["v"].get("default"))
    if kind == "missing":
        from aiset.resolver import MISSING

        return MISSING
    if kind == "object":
        return {pair[0]: decode_plain(pair[1]) for pair in value["v"]}
    if kind == "array":
        return [decode_plain(item) for item in value["v"]]
    raise ValueError(f"unknown value tag {kind!r}")


def _mutable_nodes(value: object, seen: set[int] | None = None) -> list:
    """Every mutable container reachable from
    [value], each visited once so a shared subtree is not
    counted twice."""
    seen = set() if seen is None else seen
    out: list = []
    if isinstance(value, (dict, list)):
        if id(value) in seen:
            return out
        seen.add(id(value))
        out.append(value)
        children = value.values() if isinstance(value, dict) else value
        for child in children:
            out.extend(_mutable_nodes(child, seen))
    return out


def alias_probe(base: object, update: object, merged: object) -> dict:
    """Whether the merge result shares a mutable subtree with an input.

    `aliased` is the observable answer to the purity rule of
    SPEC.md amendment 7: a result that aliases an input
    lets a later write through the result change a document the caller
    is still holding.
    """
    base_ids = {id(node) for node in _mutable_nodes(base)}
    update_ids = {id(node) for node in _mutable_nodes(update)}
    nodes = _mutable_nodes(merged)
    shares_base = sum(1 for node in nodes if id(node) in base_ids)
    shares_update = sum(1 for node in nodes if id(node) in update_ids)
    return {
        "sharesBaseNodes": shares_base,
        "sharesUpdateNodes": shares_update,
        "aliased": bool(shares_base or shares_update),
    }


def run_merge(case: dict) -> dict:
    from aiset.merge import merge

    area = case["area"]
    prefer = case["prefer"]
    base = decode_plain(case["base"])
    update = decode_plain(case["update"])
    before = copy.deepcopy(base), copy.deepcopy(update)
    try:
        merged = merge(base, update, prefer=prefer)
    except Exception as exc:  # noqa: BLE001
        return {"id": case["id"], "area": area, "ok": False, **describe_error(exc)}
    unchanged = base == before[0] and update == before[1]
    if area == "merge_immutability":
        # The aliasing probe compares the result with the actual
        # input objects: `merged` shares a subtree with
        # `base` when a node of the result is one of the nodes the
        # caller handed in.
        return {"id": case["id"], "area": area, "ok": True, "inputsUnchanged": unchanged,
                **alias_probe(base, update, merged)}
    return {
        "id": case["id"],
        "area": area,
        "ok": True,
        "merged": encode_value(merged),
        "inputsUnchanged": unchanged,
    }


# ---------------------------------------------------------------------------
# revisions (SPEC.md amendment 8)
# ---------------------------------------------------------------------------


def run_revision(case: dict) -> dict:
    from aiset.descriptor import compile_descriptor
    from aiset.store import revision_of_bytes

    operation = case["query"]["op"]
    text = case["input"]
    try:
        if operation == "source":
            revision = revision_of_bytes(text.encode("utf-8"))
            return {
                "id": case["id"],
                "area": "pipeline_revisions",
                "ok": True,
                "op": "source",
                "revision": revision,
                # UTF-16 code units, not code points:
                # an astral character (e.g. U+1F680) occupies two units.
                # Dart's String.length counts UTF-16 units, so the baseline
                # must report the same measure.
                "utf16Length": len(text.encode("utf-16-le")) // 2,
                "utf8Length": len(text.encode("utf-8")),
                "hasBom": text.startswith("\ufeff"),
            }
        if operation == "descriptor":
            compiled = compile_descriptor(text, strict=False)
            return {
                "id": case["id"],
                "area": "pipeline_revisions",
                "ok": True,
                "op": "descriptor",
                "revision": compiled.revision,
                "bytesRevision": revision_of_bytes(text.encode("utf-8")),
            }
    except Exception as exc:  # noqa: BLE001
        return {"id": case["id"], "area": "pipeline_revisions", "ok": False,
                **describe_error(exc)}
    raise SystemExit(f"unknown revision op {operation!r}")


# ---------------------------------------------------------------------------
# the write pipeline (SPEC.md amendment 8)
# ---------------------------------------------------------------------------


_SET_PORT_8080 = [{"op": "set", "path": "/port", "value_text": "8080"}]
_SET_PORT_9090 = [{"op": "set", "path": "/port", "value_text": "9090"}]
_SET_PORT_7070 = [{"op": "set", "path": "/port", "value_text": "7070"}]
_SET_HOST_OTHER = [{"op": "set", "path": "/host", "value_text": '"other"'}]
_EXTERNAL_EDIT = '{ port: 4242, host: "outside" }\n'


def run_revision_pair(case: dict) -> dict:
    """Drive the revision-pair CAS contract between two independent writers.

    Two `Service` instances are registered on one and the
    same document, which is the local-mode case
    SPEC.md amendment 8 names: the rules apply between two
    controllers or windows as well. Each writer submits
    the pair it read; the one whose pair went stale is
    refused, and the stored bytes are those the winner wrote.

    `result` keys per scenario:

    `fresh_pair`       `firstWrite`, `secondWrite`
    `stale_pair`       `secondWrite`, `staleWrite`
    `absent`           `absentWrite`
    `wrong_descriptor` `wrongDescriptor`
    `external_writer`  `externalWrite`, `staleWrite`

    plus `fileText`, the bytes the document ended with.
    """
    import tempfile as _tempfile

    from aiset.errors import AisetError
    from aiset.resolver import Resolver
    from aiset.service import Principal, Service

    area = case["area"]
    scenario = case["scenario"]
    descriptor = case["descriptor"]
    config = case["config"]

    def outcome(service, operations, revision, descriptor_revision, principal, dry=False):
        try:
            result = service.apply_operations(
                "cfg",
                operations,
                expected_revision=revision,
                expected_descriptor_revision=descriptor_revision,
                principal=principal,
                dry_run=dry,
            )
            return "stored" if result.stored else "reported"
        except AisetError as exc:
            return exc.code
        except Exception as exc:  # noqa: BLE001
            return f"{type(exc).__name__}: {exc}"[:200]

    with _tempfile.TemporaryDirectory() as raw:
        path = Path(raw) / "config.json5"
        path.write_text(config, encoding="utf-8")
        resolver = Resolver(overrides={}, dotenv={}, environ={})
        first = Service()
        first.register("cfg", path, descriptor, resolver=resolver)
        second = Service()
        second.register("cfg", path, descriptor, resolver=resolver)
        principal = Principal.demo()
        pair = (first._state("cfg").revision, first.documents["cfg"].descriptor.revision)
        out: dict = {"id": case["id"], "area": area, "ok": True, "scenario": scenario}

        if scenario == "fresh_pair":
            out["firstWrite"] = outcome(first, _SET_PORT_8080, *pair, principal)
            fresh = (first._state("cfg").revision, pair[1])
            out["secondWrite"] = outcome(second, _SET_HOST_OTHER, *fresh, principal)
        elif scenario == "stale_pair":
            out["secondWrite"] = outcome(second, _SET_PORT_9090, *pair, principal)
            out["staleWrite"] = outcome(first, _SET_PORT_7070, *pair, principal)
        elif scenario == "absent":
            out["absentWrite"] = outcome(first, _SET_PORT_8080, None, None, principal)
        elif scenario == "wrong_descriptor":
            out["wrongDescriptor"] = outcome(
                first, _SET_PORT_8080, pair[0], "sha256:" + "0" * 32, principal)
        elif scenario == "external_writer":
            # A writer outside both services replaces
            # the file; the next commit must be refused and the
            # foreign bytes must survive.
            path.write_text(_EXTERNAL_EDIT, encoding="utf-8")
            out["externalWrite"] = "stored_externally"
            out["staleWrite"] = outcome(first, _SET_PORT_7070, *pair, principal)
        out["fileText"] = path.read_text(encoding="utf-8")
        out["fileRevision"] = "sha256:" + hashlib.sha256(
            out["fileText"].encode("utf-8")).hexdigest()[:32]
        return out


# ---------------------------------------------------------------------------
# the read views (SPEC.md amendments 2 and 6)
# ---------------------------------------------------------------------------


def run_view_case(case: dict) -> dict:
    """Drive one read view through the baseline service.

    `op` selects the view:

    `effective`   the whole effective snapshot and its
                  provenance map;
    `get`         one pointer: exists, default_applied, the effective
                  value and the provenance entry for that pointer.

    Both record the descriptor and source revisions, so the
    revision pair a client would submit is pinned too.
    """
    import tempfile as _tempfile

    from aiset.errors import AisetError

    area = case["area"]
    with _tempfile.TemporaryDirectory() as raw:
        try:
            service, document, demo = make_service(Path(raw), case)
        except Exception as exc:  # noqa: BLE001
            return {"id": case["id"], "area": area, "ok": True,
                    "result": "setup_error", **describe_error(exc)}
        principal = principal_for(case, demo)
        pointer = case.get("query", {}).get("pointer", "")
        try:
            if case["query"]["op"] == "effective":
                result = service.load("cfg", principal=principal)
                payload = {
                    "effective": encode_value(result.effective),
                    "provenance": encode_value(result.provenance),
                    "revision": result.revision,
                    "descriptorRevision": result.descriptor_revision,
                    "invalidOnDisk": result.invalid_on_disk,
                }
            else:
                found = service.get("cfg", pointer, view="effective", principal=principal)
                payload = {
                    "exists": found.exists,
                    "defaultApplied": found.default_applied,
                    "effective": encode_value(found.effective),
                    "provenance": (
                        encode_value(found.provenance) if found.provenance else None
                    ),
                    "revision": found.revision,
                    "descriptorRevision": found.descriptor_revision,
                }
        except AisetError as exc:
            return {
                "id": case["id"],
                "area": area,
                "ok": True,
                "result": "rejected",
                "errorCode": exc.code,
                "errorClass": type(exc).__name__,
                "baselineCrash": False,
            }
        except Exception as exc:  # noqa: BLE001
            return {"id": case["id"], "area": area, "ok": True, "result": "crash",
                    **describe_error(exc)}
        payload["unchanged"] = document.read_bytes() == case["config"].encode("utf-8")
        # An honest probe of the SEC-01 rule: whether the
        # effective tree handed to this principal actually carries a
        # value that only the secret permission may reveal. The marker
        # arrives per case so the driver hard-codes nothing, and the answer
        # comes from executing the baseline's own view.
        marker = case.get("secretMarker")
        if marker is not None:
            tree = payload.get("effective")
            rendered = json.dumps(tree, sort_keys=True, ensure_ascii=True)
            payload["secretVisible"] = str(marker) in rendered
        return {"id": case["id"], "area": area, "ok": True,
                    "result": "viewed", "query": case["query"], **payload}


def make_service(tmp: Path, case: dict):
    """A service over one temp file, with its initial load done.

    Every layer of the resolver is passed explicitly:
    the baseline's own default for `environ` is the process environment,
    and a corpus that read it would depend on the machine it ran on.
    """
    from aiset.service import Principal, Service

    limits = case.get("limits")
    if limits:
        from aiset.store import Settings
        from aiset.validator import Limits

        service = Service(Settings(limits=Limits(**limits)))
    else:
        service = Service()
    document = tmp / "config.json5"
    document.write_text(case["config"], encoding="utf-8")
    layers = case.get("layers", {})
    resolver = Resolver(
        overrides=dict(layers.get("overrides", {})),
        dotenv=dict(layers.get("dotenv", {})),
        environ=dict(layers.get("environ", {})),
    )
    service.register("cfg", document, case["descriptor"], resolver=resolver)
    return service, document, Principal.demo()


def principal_for(case: dict, demo):
    """The actor the case names.

    `demo` is the principal the baseline's own
    `Principal.demo()` produces; the named
    variants subtract permissions from that same set so
    a case cannot silently disagree with the library about
    what the eight permissions are.
    """
    from aiset.service import PERMISSIONS, Principal

    name = case.get("principal", "demo")
    if name == "demo":
        return demo
    if name == "no_write":
        return Principal(
            id="n",
            permissions=frozenset(
                set(PERMISSIONS) - {"settings_write", "settings_edit_secret"}
            ),
        )
    if name == "no_secret_edit":
        return Principal(
            id="s", permissions=frozenset(set(PERMISSIONS) - {"settings_edit_secret"})
        )
    if name == "no_secret_read":
        return Principal(
            id="r", permissions=frozenset(set(PERMISSIONS) - {"settings_read_secret"})
        )
    if name == "validate_only":
        return Principal(
            id="v",
            permissions=frozenset(
                set(PERMISSIONS)
                - {"settings_write", "settings_edit_secret", "settings_validate"}
            ),
        )
    raise ValueError(f"unknown principal {name!r}")


def encode_pipeline_issue(issue) -> dict:
    """The observable part of a pipeline issue."""
    return {
        "rule": issue.rule,
        "path": issue.path,
        "severity": issue.severity,
        "hasMessage": bool(issue.message),
    }


def run_pipeline_case(case: dict) -> dict:
    """Drive one staged batch through the baseline service.

    The payload is labelled by `result`:

    `stored`        the batch committed;
    `rejected`      the service raised an `AisetError` and wrote nothing;
    `reported`      a dry run answered, with or without issues;
    `crash`         the baseline escaped with a non-AisetError exception;
    `setup_error`   the registration or initial load itself failed.

    Every payload records whether the stored file and the
    service's own state text changed, which is what pins the rule that
    a dry run or any pre-commit failure leaves the source
    byte-identical. The issue list is reported
    order-insensitively: which rules fire at which
    pointer is the contract, the order the walk produced them in
    is not (the same convention the descriptor and validator areas use).
    """
    import tempfile as _tempfile

    from aiset.errors import AisetError

    area = case["area"]
    with _tempfile.TemporaryDirectory() as raw:
        try:
            service, document, demo = make_service(Path(raw), case)
        except Exception as exc:  # noqa: BLE001
            return {"id": case["id"], "area": area, "ok": True,
                    "result": "setup_error", **describe_error(exc)}
        principal = principal_for(case, demo)
        initial = case["config"]
        initial_bytes = initial.encode("utf-8")

        def identity() -> dict:
            return {
                "fileUnchanged": document.read_bytes() == initial_bytes,
                "stateTextUnchanged": service._state("cfg").document.text == initial,
            }

        expected = case.get("expectedRevisions", "current")
        state = service._state("cfg")
        current_descriptor = state.registration.descriptor.revision
        if expected == "absent":
            revision, descriptor_revision = None, None
        elif expected == "stale_source":
            revision, descriptor_revision = "sha256:" + "0" * 32, current_descriptor
        elif expected == "stale_descriptor":
            revision, descriptor_revision = state.revision, "sha256:" + "0" * 32
        else:
            revision, descriptor_revision = state.revision, current_descriptor
        try:
            result = service.apply_operations(
                "cfg",
                case["operations"],
                expected_revision=revision,
                expected_descriptor_revision=descriptor_revision,
                principal=principal,
                dry_run=bool(case.get("dryRun", False)),
            )
        except AisetError as exc:
            return {
                "id": case["id"],
                "area": area,
                "ok": True,
                "result": "rejected",
                "stored": False,
                "errorCode": exc.code,
                "errorClass": type(exc).__name__,
                "baselineCrash": False,
                "issues": [
                    {
                        "rule": issue.get("rule"),
                        "path": issue.get("path"),
                        "severity": issue.get("severity", "error"),
                    }
                    for issue in exc.issues
                ],
                **identity(),
            }
        except Exception as exc:  # noqa: BLE001
            return {"id": case["id"], "area": area, "ok": True, "result": "crash",
                    **describe_error(exc), **identity()}
        payload = {
            "id": case["id"],
            "area": area,
            "ok": True,
            "result": "stored" if result.stored else "reported",
            "valid": result.valid,
            "stored": bool(result.stored),
            "dryRun": bool(result.dry_run),
            "issues": [encode_pipeline_issue(issue) for issue in result.issues],
            "changedPaths": list(result.changed_paths or []),
            **identity(),
        }
        if result.stored:
            new_state = service._state("cfg")
            payload["fileText"] = new_state.text
            payload["revision"] = new_state.revision
            payload["descriptorRevision"] = new_state.registration.descriptor.revision
            payload["activeRevision"] = new_state.active_revision
            payload["activeMatchesRevision"] = (
                new_state.active_revision == new_state.revision
            )
            payload["application"] = result.application_state
        return payload


# ---------------------------------------------------------------------------
# callbacks and subscriptions (SPEC.md amendment 9)
# ---------------------------------------------------------------------------


def run_callback_case(case: dict) -> dict:
    """Drive one host callback or subscription through the baseline service.

    `scenario` selects what is installed and what
    is submitted:

    `veto`             a `probe_changes` callback returns a Rejection
    `timeout`          a probe that outlives `callback_timeout_seconds`
    `application_fail` an `on_application` handler that raises
    `after_save_fail` an `on_after_save` observer that raises
    `subscribe_paths`  a subscription filtered by path, then a
                       write inside and a write outside it
    `unsubscribe`      the same, with the handle cancelled
    `secret_event`     a subscription and a write to a secret path

    Each payload records the committed bytes, the
    reported `stored`/`application`/`active_revision` and what the
    callback actually observed.
    """
    import tempfile as _tempfile

    from aiset.errors import AisetError
    from aiset.service import Principal, Rejection
    from aiset.validator import ValueIssue

    area = case["area"]
    scenario = case["scenario"]
    with _tempfile.TemporaryDirectory() as raw:
        try:
            service, document, principal = make_service(Path(raw), case)
        except Exception as exc:  # noqa: BLE001
            return {"id": case["id"], "area": area, "ok": True,
                    "result": "setup_error", **describe_error(exc)}
        state = service._state("cfg")
        pair = (state.revision, state.registration.descriptor.revision)
        seen: dict = {"probe": [], "after_save": [], "application": [], "events": []}

        def submit(path="/port", value="8080"):
            try:
                result = service.apply_operations(
                    "cfg",
                    [{"op": "set", "path": path, "value_text": value}],
                    expected_revision=pair[0],
                    expected_descriptor_revision=pair[1],
                    principal=principal,
                )
                return {
                    "stored": bool(result.stored),
                    "application": result.application_state,
                    "revision": result.revision,
                    "activeRevision": result.active_revision,
                    "fileText": document.read_text(encoding="utf-8"),
                }
            except AisetError as exc:
                return {
                    "stored": False,
                    "errorCode": exc.code,
                    "issueRules": [issue.get("rule") for issue in exc.issues],
                    "fileText": document.read_text(encoding="utf-8"),
                }

        out: dict = {"id": case["id"], "area": area, "ok": True, "scenario": scenario}

        if scenario == "veto":
            def veto(before, after, changed_paths):
                seen["probe"].append({"paths": list(changed_paths), "after": after})
                return Rejection([ValueIssue("/port", "veto", "host says no")])

            service.on_probe_changes(veto)
        elif scenario == "timeout":
            import time

            # A Service reads the bound from its
            # settings object; the registration
            # snapshot above copied the store settings,
            # so the timeout is set where it takes effect.
            service.settings.callback_timeout_seconds = 0.05

            def slow(before, after, changed_paths):
                seen["probe"].append("called")
                time.sleep(0.5)

            service.on_probe_changes(slow)
        elif scenario == "application_fail":
            def boom(previous, current, changed_paths):
                seen["application"].append({"paths": list(changed_paths)})
                raise RuntimeError("host apply failed")

            service.on_application(boom)
        elif scenario == "after_save_fail":
            def bad(previous, current, event):
                seen["after_save"].append(event)
                raise RuntimeError("observer blew up")

            service.on_after_save(bad)
        elif scenario in ("subscribe_paths", "unsubscribe", "secret_event"):
            def listener(event):
                seen["events"].append(
                    {
                        "document": event.document,
                        "changed_paths": list(event.changed_paths),
                        "previous": event.previous_revision,
                        "revision": event.revision,
                        "application": event.application_state,
                        "active": event.active_revision,
                    }
                )

            subscriber = principal
            if scenario == "secret_event":
                from aiset.service import PERMISSIONS

                subscriber = Principal(
                    id="r",
                    permissions=frozenset(set(PERMISSIONS) - {"settings_read_secret"}),
                )
                # The writer is a different actor with the
                # edit permission, so the only thing
                # missing here is the subscriber's right to
                # see the path it subscribed to.
                principal = Principal(id="w", permissions=frozenset(PERMISSIONS))
            handle = service.subscribe(
                "cfg", case.get("paths", ["/port"]), listener, principal=subscriber
            )
            if scenario == "unsubscribe":
                handle.unsubscribe()
        else:
            raise SystemExit(f"unknown callback scenario {scenario!r}")

        out.update(submit(case.get("path", "/port"), case.get("value", "8080")))
        if scenario == "subscribe_paths":
            # A second write outside the watched path.
            service.states["cfg"] = service._state("cfg")
            fresh = service._state("cfg")
            try:
                service.apply_operations(
                    "cfg",
                    [{"op": "set", "path": case.get("other", "/host"), "value_text": '"o"'}],
                    expected_revision=fresh.revision,
                    expected_descriptor_revision=pair[1],
                    principal=principal,
                )
            except AisetError as exc:
                out["otherWrite"] = exc.code
        out["probeCalls"] = len(seen["probe"])
        out["applicationCalls"] = len(seen["application"])
        out["afterSaveCalls"] = len(seen["after_save"])
        out["events"] = seen["events"]
        if seen["probe"] and scenario == "veto":
            out["probeSawAfter"] = encode_value(seen["probe"][0]["after"])
        return out


RUNNERS = {
    "parse": run_parse,
    "query": run_query,
    "operation": run_operation,
    "descriptor_validate": run_descriptor_validate,
    "descriptor_compile": run_descriptor_compile,
    "descriptor_query": run_descriptor_query,
    "resolver_lookup": run_resolver_lookup,
    "resolver_text": run_resolver_text,
    "resolver_effective": run_resolver_effective,
    "validator_profile": run_validator_profile,
    "validator_value": run_validator_value,
    "merge": run_merge,
    "revision": run_revision,
    "pipeline_revision_pair": run_revision_pair,
    "pipeline_case": run_pipeline_case,
    "pipeline_view": run_view_case,
    "pipeline_callback": run_callback_case,
}


def generator_hash(paths: list[str]) -> str:
    """Content hash over the generator's own source files."""
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.encode("utf-8"))
        digest.update(Path(path).read_bytes())
    return digest.hexdigest()


def main() -> int:
    job = json.load(sys.stdin)
    results = []
    for case in job["cases"]:
        runner = RUNNERS.get(case.get("kind"))
        if runner is None:
            raise SystemExit(f"unknown case kind {case.get('kind')!r} for case {case.get('id')!r}")
        results.append(runner(case))
    payload = {"results": results}
    if job.get("hash_files"):
        payload["generator_sha256"] = generator_hash(list(job["hash_files"]))
    json.dump(payload, sys.stdout, sort_keys=True, ensure_ascii=True, indent=1)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
