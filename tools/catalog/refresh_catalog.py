#!/usr/bin/env python3
"""Regenerates the bundled UNC Charlotte BSME dataset (Packages/ThubanPlannerCore/Sources/ThubanPlannerCore/
Resources/uncc-bsme-2025-26.json) from the public catalog, catalog.charlotte.edu (acalog), read-only.

    scripts/refresh_catalog.sh            # or: python3 tools/catalog/refresh_catalog.py [--out path] [--no-cache]

What it reads (headless Chromium — the catalog's AWS WAF challenge needs JavaScript):
  1. the BSME program page (catoid 40 = 2025-2026, poid 11501): core courses, the Technical Elective list + rule;
  2. the subject course listings ("Course Descriptions", navoid 4989) for every subject it meets, to map codes to
     course ids (coids) — prerequisites are not always links;
  3. each elective's course page, then RECURSIVELY each prerequisite / corequisite it names, stopping at BSME core
     courses (whose own pages are read too, without recursing) and courses with no requirements.
Pages are cached in /tmp/thuban-catalog-pages (delete it or pass --no-cache to refetch); requests are paced (1 s).
Requirement text is parsed by reqparse.py (the same rules as the app's CatalogRequirementParser)."""
import argparse, datetime, html as H, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch import fetch  # noqa: E402
from reqparse import parse  # noqa: E402

BASE = "https://catalog.charlotte.edu"
CATOID = 40
POID = 11501
NAVOID = 4989
# Codes that have no page in 2025-26 (DegreeWorks lists a few newer electives) are looked up in 2026-27.
NEXT_CATOID = 42
NEXT_NAVOID = 5390
NEXT_YEAR = "2026-2027"
CATALOG_YEAR = "2025-2026"

# The Technical Elective block of a UNC Charlotte DegreeWorks audit for the BSME, catalog year 2025-2026
# (read 2026-09-26): "4 Classes in MEGR 3090 or 3092 … or PHYS 4271 — additionally you need a minimum of 3 Classes in
# MEGR @". Kept verbatim (codes only) so the dataset can say where the audit and the catalog disagree.
DEGREEWORKS = ("MEGR 3090 3092 3094 3097 3162 3210 3211 3214 3222 3225 3231 3232 3233 3234 3235 3236 3237 3238 3240 3241 3242 "
               "3243 3244 3245 3260 3261 3262 3270 3271 3272 3280 3282 3283 3310 4091 3451 3452 4090 4092 4094 4097 4098 "
               "4127 4143 4210 4211 4212 4213 4235 4237 4240 4242 4244 4271 4272 4273 4274 4280 4281 4282 4290 4291 4292 "
               "4310 4311 4312 4313 | BIOL 3161 | MATH 3171 | PHYS 3220 4110 4140 4232 4242 4271")


def dw_codes():
    out = []
    for part in DEGREEWORKS.split("|"):
        words = part.split()
        out += [f"{words[0]} {n}" for n in words[1:]]
    return out


def text_of(fragment):
    t = re.sub(r'<span style="display: none !important">&nbsp;</span>', "", fragment)
    t = re.sub(r"<br\s*/?>", "\n", t)
    t = re.sub(r"</(p|li|h\d|div)>", "\n", t)
    t = re.sub(r"<[^>]+>", "", t)
    return H.unescape(t).replace(" ", " ")


def norm(code):
    m = re.match(r"\s*([A-Za-z]{2,4})\s*(\d{4}[A-Za-z]?)\s*$", code)
    return f"{m.group(1).upper()} {m.group(2).upper()}" if m else code.strip().upper()


def program():
    url = f"{BASE}/preview_program.php?catoid={CATOID}&poid={POID}"
    s = fetch(url)
    title = re.search(r'<h1[^>]*id="acalog-page-title"[^>]*>(.*?)</h1>', s, re.S)
    title = text_of(title.group(1)).strip() if title else "Mechanical Engineering, B.S.M.E."
    coids = {}
    for coid, code in re.findall(r"showCourse\('%d', '(\d+)'[^>]*>([A-Z]{3,4} \d{4}[A-Z]?)" % CATOID, s):
        coids[norm(code)] = coid
    for coid, code in re.findall(r'coid=(\d+)&amp;print[^>]*aria-label="View course details for ([A-Z]{3,4} \d{4}[A-Z]?)"', s):
        coids.setdefault(norm(code), coid)
    text = text_of(s)
    start = text.find("Technical Elective Courses")
    end = text.find("Unrestricted Elective Courses", start)
    block = text[start:end]
    head = re.search(r"Technical Elective Courses \((\d+) credit hours\)", block)
    rule = re.search(r"(Select [^\n]*?\.(?:\s*At least[^\n]*?\.)?)", block)
    electives = []
    for line in block.splitlines():
        m = re.match(r"\s*•?\s*([A-Z]{3,4} \d{4}[A-Z]?) - (.*?) \((\d+(?:-\d+)?)\)\s*(\((.*)\))?\s*$", line.strip())
        if m:
            electives.append({"code": m.group(1), "title": m.group(2).strip(), "credits": m.group(3),
                              "note": (m.group(5) or "").strip() or None})
    core_start = text.find("Degree Requirements\n")
    core_block = text[text.find("Additional Math and Physics Courses", core_start):start]
    core = sorted({norm(c) for c in re.findall(r"\b([A-Z]{3,4} \d{4}[A-Z]?) - ", core_block)})
    cfy = ["ENGR 1300", "ENGR 1301", "ENGR 1302", "ENGR 1303", "MATH 1241", "MATH 1242", "PHYS 2101", "PHYS 2101L"]
    return {"url": url, "title": title, "coids": coids, "electives": electives,
            "credits": int(head.group(1)) if head else 12, "rule": rule.group(1).strip() if rule else "",
            "core": sorted(set(core) | set(cfy))}


_listing = {}


def subject_coids(subject, catoid=CATOID, navoid=NAVOID):
    if (subject, catoid) in _listing:
        return _listing[(subject, catoid)]
    found, page = {}, 1
    while page <= 6:
        url = (f"{BASE}/content.php?filter%5B27%5D={subject}&filter%5B29%5D=&filter%5Bkeyword%5D=&filter%5B32%5D=1"
               f"&filter%5Bcpage%5D={page}&cur_cat_oid={catoid}&expand=&navoid={navoid}&search_database=Filter"
               f"&filter%5Bexact_match%5D=1")
        s = fetch(url)
        hits = re.findall(r"coid=(\d+)[^>]*>\s*(%s\s*\d{4}[A-Z]?)(?:\s|&nbsp;)*-" % subject, s)
        for coid, code in hits:
            found.setdefault(norm(code), coid)
        pages = [int(p) for p in re.findall(r"filter%5Bcpage%5D=(\d+)", s)]
        if not hits or page >= max(pages or [1]):
            break
        page += 1
    _listing[(subject, catoid)] = found
    return found


def course(coid, code, catoid=CATOID):
    url = f"{BASE}/preview_course_nopop.php?catoid={catoid}&coid={coid}"
    s = fetch(url)
    i = s.find('<h1 id="course_preview_title"')
    j = s.find("portfolio.php", i)
    seg = s[i:j]
    h1 = re.search(r"<h1[^>]*>(.*?)</h1>", seg, re.S)
    head = text_of(h1.group(1)).strip() if h1 else code
    title = head.split(" - ", 1)[1].strip() if " - " in head else head
    body = text_of(seg[h1.end():] if h1 else seg)
    fields = {}
    for label, key in [("Credit Hours:", "credits"), ("Prerequisite(s):", "prereq"), ("Corequisite(s):", "coreq"),
                       ("Pre- or Corequisite(s):", "precoreq"), ("Restriction(s):", "restriction"),
                       ("Cross-listed with", "crossListed")]:
        for line in body.splitlines():
            line = line.strip()
            if line.startswith(label):
                fields[key] = line[len(label):].strip(" :")
                break
    desc = body.split("Credit Hours:")[0].strip()
    credits_text = fields.get("credits", "")
    m = re.search(r"\((\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?\)", credits_text)
    credits = float(m.group(1)) if m else None
    if catoid != CATOID:
        linked = {}
        return {"code": code, "title": title, "credits": credits, "creditsText": credits_text or None,
                "description": desc[:600] or None, "prereqText": fields.get("prereq"), "coreqText": fields.get("coreq"),
                "preOrCoreqText": fields.get("precoreq"), "restriction": fields.get("restriction"),
                "catalogURL": url, "coid": coid, "linked": linked, "catalogYear": NEXT_YEAR}
    linked = {norm(c): k for k, c in re.findall(r'coid=(\d+)&amp;print[^>]*aria-label="View course details for ([A-Z]{3,4} \d{4}[A-Z]?)"', seg)}
    return {"code": code, "title": title, "credits": credits, "creditsText": credits_text or None,
            "description": desc[:600] or None, "prereqText": fields.get("prereq"), "coreqText": fields.get("coreq"),
            "preOrCoreqText": fields.get("precoreq"), "restriction": fields.get("restriction"),
            "catalogURL": url, "coid": coid, "linked": linked}


def build(out_path):
    prog = program()
    coids = dict(prog["coids"])
    catalog_list = [e["code"] for e in prog["electives"]]
    dw = dw_codes()
    elective_codes = list(dict.fromkeys(catalog_list + [c for c in dw if c not in catalog_list]))
    core = set(prog["core"])

    def coid_for(code):
        if code in coids:
            return coids[code]
        subj = code.split()[0]
        found = subject_coids(subj)
        coids.update({k: v for k, v in found.items() if k not in coids})
        return coids.get(code)

    courses, missing = {}, []
    queue = list(elective_codes) + sorted(core)
    seen = set()
    while queue:
        code = queue.pop(0)
        if code in seen:
            continue
        seen.add(code)
        coid = coid_for(code)
        if coid:
            c = course(coid, code)
        else:
            missing.append(code)
            nxt = subject_coids(code.split()[0], NEXT_CATOID, NEXT_NAVOID).get(code)
            if not nxt:
                continue
            c = course(nxt, code, NEXT_CATOID)
        coids.update(c.pop("linked"))
        groups, notes = [], []
        for key in ("prereqText", "coreqText", "preOrCoreqText"):
            g, n = parse(c[key] or "")
            c[{"prereqText": "prereqGroups", "coreqText": "coreqGroups", "preOrCoreqText": "preOrCoreqGroups"}[key]] = g
            notes += n
            groups += g
        if c.get("restriction"):
            notes.insert(0, c["restriction"])
        c["notes"] = list(dict.fromkeys(notes))
        c["core"] = code in core
        courses[code] = c
        if code in core:
            continue  # stop at the BSME core: its requirements are already in the degree
        for g in groups:
            for ref in g:
                if ref not in seen:
                    queue.append(ref)
        print(f"  {code}: {c['title']} ({c['credits']}) prereq={c['prereqGroups']} coreq={c['coreqGroups']} "
              f"pre/co={c['preOrCoreqGroups']}", file=sys.stderr)

    by_note = {e["code"]: e["note"] for e in prog["electives"]}
    electives = []
    for code in elective_codes:
        electives.append({"code": code, "inCatalog": code in catalog_list, "inDegreeWorks": code in dw,
                          "megr": code.startswith("MEGR "), "condition": by_note.get(code),
                          "existsInCatalog": code in courses and not courses[code].get("catalogYear")})
    doc = {
        "version": 1,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
        "generator": "tools/catalog/refresh_catalog.py",
        "program": {
            "id": "uncc-bsme-2025-26", "name": "Mechanical Engineering, B.S.M.E.", "catalogTitle": prog["title"],
            "school": "UNC Charlotte", "catalogYear": CATALOG_YEAR, "catalogURL": prog["url"],
            "techElectives": {"label": "Technical electives", "count": 4, "credits": prog["credits"],
                              "minimumMEGR": 3, "rule": prog["rule"],
                              "degreeWorks": "4 Classes in MEGR 3090 or … or PHYS 4271 — additionally a minimum of 3 Classes in MEGR @"},
            "core": prog["core"],
        },
        "sources": [prog["url"], f"{BASE}/content.php?catoid={CATOID}&navoid={NAVOID} (course descriptions)",
                    "UNC Charlotte DegreeWorks audit, BSME catalog year 2025-2026, Technical Elective block (2026-09-26)"],
        "electives": electives,
        "missingFromCatalog": sorted(set(missing)),
        "nextCatalogYear": NEXT_YEAR,
        "courses": dict(sorted(courses.items())),
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {out_path}: {len(electives)} electives, {len(courses)} courses, missing {doc['missingFromCatalog']}",
          file=sys.stderr)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    default = os.path.join(here, "..", "..", "Packages", "ThubanPlannerCore", "Sources", "ThubanPlannerCore", "Resources",
                           "uncc-bsme-2025-26.json")
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.normpath(default))
    ap.add_argument("--no-cache", action="store_true")
    a = ap.parse_args()
    if a.no_cache:
        os.environ["CATALOG_PAGE_CACHE"] = "/tmp/thuban-catalog-pages-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    build(a.out)
