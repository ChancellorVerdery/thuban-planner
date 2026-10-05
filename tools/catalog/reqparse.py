"""Requirement-text parser for UNC Charlotte catalog lines ("MATH 2171, MEGR 2144, and either MEGR 2240 or MEGR 2242
with grades of C or above"). Mirrors ThubanPlannerCore's `CatalogRequirementParser` (Swift) rule for rule; the core's
tests check that both agree on every course in the bundled dataset. Output: AND of OR-groups ([["A"], ["B", "C"]])
plus notes for the conditions that are not courses (grades, standing, permission)."""
import re

CODE = re.compile(r"\b([A-Z]{3,4})\s?(\d{4}[A-Z]?)\b")
GRADE = re.compile(r"\b(?:all\s+|both\s+|each\s+)?(?:with\s+)?(?:an?\s+)?(?:minimum\s+)?(?:grades?\s+of\s+)?(?:at\s+least\s+)?(?:an?\s+)?\"?[A-D][+-]?\"?\s+or\s+(?:above|better|higher)\b", re.I)
WAIVER = re.compile(r"\bor\s+(?:the\s+)?(?:permission|consent|approval)\s+of\s+(?:the\s+)?(?:instructor|department|program director|department chair|chair)\b|\bor\s+(?:the\s+)?(?:equivalent|permission|consent)\b", re.I)


def tokens(text):
    """Course codes (subject carried over to bare numbers), 'and', 'or', ',', ';', '(', ')'. Other words drop."""
    out = []
    subject = None
    i = 0
    pat = re.compile(r"\b([A-Z]{3,4})\s?(\d{4}[A-Z]?)\b|\b(\d{4}[A-Z]?)\b|\b((?i:and|or))\b|([,;()])")
    for m in pat.finditer(text):
        if m.group(1):
            subject = m.group(1)
            out.append(("code", f"{m.group(1)} {m.group(2)}"))
        elif m.group(3):
            prev = out[-1][0] if out else None
            if subject and prev in ("and", "or", ",", ";", "("):
                out.append(("code", f"{subject} {m.group(3)}"))
        elif m.group(4):
            out.append((m.group(4).lower(), None))
        else:
            out.append((m.group(5), None))
    return out


def _parse_seq(toks, i):
    """Parses until ')' or end. Returns (expr, next index). expr: ('c', code) | ('and', [..]) | ('or', [..]) | None"""
    items, seps = [], []
    pending = []
    while i < len(toks):
        kind, val = toks[i]
        if kind == ")":
            i += 1
            break
        if kind == "(":
            sub, i = _parse_seq(toks, i + 1)
            if sub is not None:
                if items and pending is not None and len(seps) < len(items):
                    seps.append(_strongest(pending))
                items.append(sub)
                pending = []
            continue
        if kind == "code":
            if items and len(seps) < len(items):
                seps.append(_strongest(pending))
            items.append(("c", val))
            pending = []
        else:
            pending.append(kind)
        i += 1
    return _combine(items, seps), i


def _strongest(pending):
    if ";" in pending:
        return ";"
    if "and" in pending:
        return "and"
    if "or" in pending:
        return "or"
    if "," in pending:
        return ","
    return "and"  # adjacent codes with only words between ("MEGR 3121 (…) PHYS 3101") — conservative AND


def _combine(items, seps):
    if not items:
        return None
    if len(items) == 1:
        return items[0]
    # ';' splits first (lowest precedence), each part combined on its own.
    if ";" in seps:
        parts, cur, cur_seps = [], [items[0]], []
        for s, it in zip(seps, items[1:]):
            if s == ";":
                parts.append(_combine(cur, cur_seps))
                cur, cur_seps = [it], []
            else:
                cur.append(it)
                cur_seps.append(s)
        parts.append(_combine(cur, cur_seps))
        return ("and", [p for p in parts if p is not None])
    comma = "and" if "and" in seps else ("or" if "or" in seps else "and")
    seps = [comma if s == "," else s for s in seps]
    groups, cur = [], [items[0]]
    for s, it in zip(seps, items[1:]):
        if s == "and":
            groups.append(cur)
            cur = [it]
        else:
            cur.append(it)
    groups.append(cur)
    ands = [g[0] if len(g) == 1 else ("or", g) for g in groups]
    return ands[0] if len(ands) == 1 else ("and", ands)


def cnf(expr):
    """Expression → AND of OR-groups (codes), distributed, de-duplicated, capped."""
    if expr is None:
        return []
    k = expr[0]
    if k == "c":
        return [[expr[1]]]
    if k == "and":
        out = []
        for e in expr[1]:
            out += cnf(e)
        return _dedupe(out)
    # or: distribute
    acc = [[]]
    for e in expr[1]:
        sub = cnf(e)
        if not sub:
            continue
        acc = [a + b for a in acc for b in sub][:64]
    return _dedupe(acc)


def _dedupe(groups):
    out, seen = [], set()
    for g in groups:
        g2 = []
        for c in g:
            if c not in g2:
                g2.append(c)
        key = tuple(sorted(g2))
        if g2 and key not in seen:
            seen.add(key)
            out.append(g2)
    # drop groups that are supersets of another group (A ∧ (A ∨ B) = A)
    return [g for g in out if not any(set(h) < set(g) for h in out)]


def parse(text):
    """→ (groups, notes)"""
    if not text:
        return [], []
    notes = []
    t = text.replace(" ", " ")
    for m in GRADE.finditer(t):
        notes.append(re.sub(r"\s+", " ", m.group(0).strip()))
    t = GRADE.sub(" ", t)
    for m in WAIVER.finditer(t):
        notes.append(re.sub(r"\s+", " ", m.group(0).strip()))
    t = WAIVER.sub(" ", t)
    # Parenthetical asides without a course code are notes.
    def aside(m):
        inner = m.group(1)
        rest = CODE.sub(" ", inner)
        rest = re.sub(r"(?i)\b(and|or|either|both|one|of|the|following)\b|[,;]", " ", rest)
        if CODE.search(inner) and len(rest.split()) <= 1:
            return m.group(0)
        notes.append(inner.strip())
        return " "
    t = re.sub(r"\(([^()]*)\)", aside, t)
    expr, _ = _parse_seq(tokens(t), 0)
    return cnf(expr), notes
