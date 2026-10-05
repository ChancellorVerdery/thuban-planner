"""Headless-Chromium page fetcher for catalog.charlotte.edu (acalog), which sits behind an AWS WAF JavaScript
challenge that plain HTTP clients cannot pass. Uses Playwright's cached chrome-headless-shell (no Node needed)."""
import glob, os, subprocess, time, hashlib

CACHE_DIR = os.environ.get("CATALOG_PAGE_CACHE", "/tmp/thuban-catalog-pages")
PROFILE = os.environ.get("CATALOG_PROFILE", "/tmp/thuban-catalog-profile")
PAUSE = float(os.environ.get("CATALOG_PAUSE", "1.0"))
_last = [0.0]


def chromium():
    env = os.environ.get("CHROMIUM")
    if env:
        return env
    pats = [os.path.expanduser("~/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-mac-*/chrome-headless-shell"),
            os.path.expanduser("~/Library/Caches/ms-playwright/chromium-*/chrome-mac*/Chromium.app/Contents/MacOS/Chromium")]
    for p in pats:
        hits = sorted(glob.glob(p))
        if hits:
            return hits[-1]
    raise SystemExit("No headless Chromium found (set CHROMIUM=/path/to/chrome-headless-shell).")


def fetch(url, use_cache=True):
    os.makedirs(CACHE_DIR, exist_ok=True)
    key = os.path.join(CACHE_DIR, hashlib.sha1(url.encode()).hexdigest() + ".html")
    if use_cache and os.path.exists(key) and os.path.getsize(key) > 2000:
        return open(key, encoding="utf-8", errors="replace").read()
    for attempt in range(3):
        wait = PAUSE - (time.time() - _last[0])
        if wait > 0:
            time.sleep(wait)
        out = subprocess.run([chromium(), "--headless", "--disable-gpu", "--virtual-time-budget=15000",
                              f"--user-data-dir={PROFILE}", "--dump-dom", url],
                             capture_output=True, timeout=120)
        _last[0] = time.time()
        html = out.stdout.decode("utf-8", errors="replace")
        if "acalog" in html and len(html) > 5000:
            open(key, "w", encoding="utf-8").write(html)
            return html
        time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"Could not load {url}")
