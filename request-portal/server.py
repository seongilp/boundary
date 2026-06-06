#!/usr/bin/env python3
"""
Boundary 접근권한 신청 포털 (PoC).
웹폼 제출 → terraform/access.json 수정 → GitHub PR 자동 생성 (GitOps).
승인자가 PR 머지 → CI(또는 운영자 apply.sh)가 terraform apply.

의존성 없음(파이썬 표준 라이브러리 + gh/git CLI). UI 는 Tailwind + Lucide CDN.
실행:  python3 server.py   (http://127.0.0.1:8090)
"""
import json, os, subprocess, tempfile, shutil, time, html
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

REPO = "seongilp/boundary"
USERS = ["alice", "carol", "bob"]
TARGETS = ["ssh-target", "pg-target", "pg-dyn-target", "redis-target", "web-target", "k8s-target"]
PORT = 8090


def run(args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=True)


def create_pr(requester, target, reason, duration):
    """access.json 에 (requester→target) 추가하는 PR 생성. (pr_url, error) 반환."""
    ts = int(time.time())
    branch = f"access/{requester}-{target}-{ts}"
    work = tempfile.mkdtemp(prefix="bdy-req-")
    try:
        run(["gh", "repo", "clone", REPO, work, "--", "--depth", "1"])
        path = os.path.join(work, "terraform", "access.json")
        with open(path) as f:
            data = json.load(f)
        data.setdefault(requester, [])
        if target in data[requester]:
            return None, f"{requester} 는 이미 {target} 권한이 있습니다."
        data[requester].append(target)
        with open(path, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        run(["git", "checkout", "-b", branch], cwd=work)
        run(["git", "add", "terraform/access.json"], cwd=work)
        run(["git", "commit", "-m", f"access: {requester} -> {target}"], cwd=work)
        run(["git", "push", "-u", "origin", branch], cwd=work)
        body = (f"## Boundary 접근권한 신청\n\n"
                f"- **신청자**: {requester}\n- **대상**: {target}\n"
                f"- **사유**: {reason}\n- **기간**: {duration}\n\n"
                f"승인(머지) 시 `terraform apply` 로 권한이 부여됩니다.")
        out = run(["gh", "pr", "create", "--repo", REPO, "--base", "main",
                   "--head", branch, "--title", f"[access] {requester} -> {target}",
                   "--body", body], cwd=work)
        return out.stdout.strip(), None
    except subprocess.CalledProcessError as e:
        return None, (e.stderr or e.stdout or str(e))
    finally:
        shutil.rmtree(work, ignore_errors=True)


PAGE = """<!DOCTYPE html><html lang="ko" class="dark"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Boundary Access Request</title>
<script src="https://cdn.tailwindcss.com"></script>
<script src="https://unpkg.com/lucide@latest"></script>
<style>
  body{background:
    radial-gradient(900px 500px at 85% -10%,rgba(124,92,255,.20),transparent 60%),
    radial-gradient(700px 420px at 0% 110%,rgba(56,189,248,.12),transparent 55%),
    #07080c;}
  select,input,textarea{background-color:rgb(2 6 23 / .7)!important}
  option{background:#0b1020;color:#e2e8f0}
</style></head>
<body class="min-h-screen text-slate-100 antialiased flex items-center justify-center p-5"
  style="font-family:-apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo','Segoe UI',Roboto,sans-serif">
<div class="w-full max-w-md">

  <div class="flex items-center gap-3 mb-2">
    <div class="w-10 h-10 rounded-xl grid place-items-center text-white shadow-lg shadow-violet-600/40
      bg-gradient-to-br from-violet-500 to-sky-500">
      <i data-lucide="shield-check" class="w-5 h-5"></i>
    </div>
    <h1 class="text-lg font-semibold tracking-tight">Boundary Access</h1>
    <a href="/admin" class="ml-auto text-[12px] text-slate-400 hover:text-slate-200 flex items-center gap-1">
      <i data-lucide="settings" class="w-3.5 h-3.5"></i>운영자</a>
  </div>
  <p class="text-slate-400 text-[13.5px] mb-5">접근권한을 신청하면 변경 PR 이 자동 생성됩니다. 승인자가 머지하면 부여돼요.</p>

  <div class="rounded-2xl border border-slate-700/60 p-6 shadow-2xl shadow-black/50
    bg-gradient-to-b from-slate-900/90 to-slate-950/90 backdrop-blur">
    <form method="POST" action="/request" class="space-y-4">
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[11px] font-semibold uppercase tracking-wider text-slate-400 mb-1.5">신청자</label>
          <div class="relative">
            <i data-lucide="user" class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none"></i>
            <select name="requester"
              class="w-full appearance-none border border-slate-700/70 rounded-xl text-sm text-slate-100 pl-9 pr-3 py-2.5 outline-none focus:border-violet-500 focus:ring-2 focus:ring-violet-500/25 transition">__USERS__</select>
          </div>
        </div>
        <div>
          <label class="block text-[11px] font-semibold uppercase tracking-wider text-slate-400 mb-1.5">대상 리소스</label>
          <div class="relative">
            <i data-lucide="server" class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none"></i>
            <select name="target"
              class="w-full appearance-none border border-slate-700/70 rounded-xl text-sm text-slate-100 pl-9 pr-3 py-2.5 outline-none focus:border-violet-500 focus:ring-2 focus:ring-violet-500/25 transition">__TARGETS__</select>
          </div>
        </div>
      </div>
      <div>
        <label class="block text-[11px] font-semibold uppercase tracking-wider text-slate-400 mb-1.5">사유</label>
        <div class="relative">
          <i data-lucide="file-text" class="w-4 h-4 absolute left-3 top-3 text-slate-500 pointer-events-none"></i>
          <textarea name="reason" required rows="2" placeholder="예) 결제 버그 조사 - 읽기 필요"
            class="w-full border border-slate-700/70 rounded-xl text-sm text-slate-100 pl-9 pr-3 py-2.5 outline-none resize-y focus:border-violet-500 focus:ring-2 focus:ring-violet-500/25 transition"></textarea>
        </div>
      </div>
      <div>
        <label class="block text-[11px] font-semibold uppercase tracking-wider text-slate-400 mb-1.5">필요 기간</label>
        <div class="relative">
          <i data-lucide="calendar-clock" class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 pointer-events-none"></i>
          <input name="duration" required placeholder="예) 2026-06-10 ~ 06-17 (또는 영구)"
            class="w-full border border-slate-700/70 rounded-xl text-sm text-slate-100 pl-9 pr-3 py-2.5 outline-none focus:border-violet-500 focus:ring-2 focus:ring-violet-500/25 transition">
        </div>
      </div>
      <button type="submit" class="w-full flex items-center justify-center gap-2 rounded-xl py-3 font-bold
        text-white bg-gradient-to-r from-violet-500 to-sky-500 shadow-lg shadow-violet-600/40
        hover:brightness-110 active:translate-y-px transition">
        <i data-lucide="git-pull-request-arrow" class="w-4 h-4"></i> 접근권한 신청
      </button>
    </form>
    __MSG__
  </div>

  <p class="text-center text-[12px] text-slate-500 mt-5 leading-relaxed">
    <b class="text-violet-300">신청</b> → PR 자동생성 → 승인자 <b class="text-violet-300">머지</b>
    → terraform apply → <b class="text-violet-300">권한 부여</b>
  </p>
</div>
<script>lucide.createIcons();</script>
</body></html>"""


ADMIN = """<!DOCTYPE html><html lang="ko" class="dark"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Boundary Admin</title>
<script src="https://cdn.tailwindcss.com"></script>
<script src="https://unpkg.com/lucide@latest"></script>
<style>body{background:
  radial-gradient(900px 500px at 85% -10%,rgba(124,92,255,.20),transparent 60%),
  radial-gradient(700px 420px at 0% 110%,rgba(56,189,248,.12),transparent 55%),#07080c;}</style>
</head>
<body class="min-h-screen text-slate-100 antialiased flex items-start justify-center p-5"
  style="font-family:-apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo','Segoe UI',Roboto,sans-serif">
<div class="w-full max-w-2xl mt-6">
  <div class="flex items-center gap-3 mb-2">
    <div class="w-10 h-10 rounded-xl grid place-items-center text-white shadow-lg shadow-violet-600/40
      bg-gradient-to-br from-violet-500 to-sky-500"><i data-lucide="shield-check" class="w-5 h-5"></i></div>
    <h1 class="text-lg font-semibold tracking-tight">Boundary Admin</h1>
    <a href="/" class="ml-auto text-[12px] text-slate-400 hover:text-slate-200 flex items-center gap-1">
      <i data-lucide="arrow-left" class="w-3.5 h-3.5"></i>신청 페이지</a>
  </div>
  <p class="text-slate-400 text-[13.5px] mb-5">접근권한 신청을 승인하면 즉시 적용(terraform apply)됩니다.</p>
  __MSG__
  <div class="rounded-2xl border border-slate-700/60 p-5 mb-4 bg-gradient-to-b from-slate-900/90 to-slate-950/90 backdrop-blur">
    <div class="flex items-center gap-2 mb-3 text-slate-300 font-semibold text-sm">
      <i data-lucide="inbox" class="w-4 h-4 text-violet-300"></i>대기 중인 신청</div>
    __PRS__
  </div>
  <div class="rounded-2xl border border-slate-700/60 p-5 bg-gradient-to-b from-slate-900/90 to-slate-950/90 backdrop-blur">
    <div class="flex items-center gap-2 mb-3 text-slate-300 font-semibold text-sm">
      <i data-lucide="grid-3x3" class="w-4 h-4 text-violet-300"></i>현재 권한 매트릭스
      <span class="text-[11px] text-slate-500 font-normal">(● 허용 / ○ 차단)</span></div>
    <table class="w-full text-sm"><thead><tr>
      <th class="text-left px-2 py-2 font-medium text-slate-400 text-[11px]">사용자</th>__HEADS__
    </tr></thead><tbody>__ROWS__</tbody></table>
  </div>
  <p class="text-center text-[12px] text-slate-500 mt-5">access.json 기준 · 승인 시 PR 머지 → apply</p>
</div>
<script>lucide.createIcons();</script>
</body></html>"""


def render(msg=""):
    users = "".join(f"<option>{u}</option>" for u in USERS)
    targets = "".join(f"<option>{t}</option>" for t in TARGETS)
    return (PAGE.replace("__USERS__", users)
                .replace("__TARGETS__", targets)
                .replace("__MSG__", msg))


def msg_ok(url):
    u = html.escape(url)
    return (f'<div class="mt-4 rounded-xl border border-emerald-500/40 bg-emerald-500/10 p-3.5 text-[13px] text-emerald-200 flex gap-2">'
            f'<span>✅</span><div>신청 완료 — PR 생성됨<br><a class="text-sky-300 underline break-all" href="{u}" target="_blank">{u}</a></div></div>')


def msg_err(err):
    return (f'<div class="mt-4 rounded-xl border border-rose-500/40 bg-rose-500/10 p-3.5 text-[13px] text-rose-200 flex gap-2">'
            f'<span>❌</span><div class="break-all">{html.escape(err)}</div></div>')


# ──────────────────────────────────────────────
# 운영자(Admin) 페이지 — 신청 PR 승인 + 권한 매트릭스
# (PoC: 신청 포털과 한 서버에 둠. 나중엔 별도 서비스/인증으로 분리)
# ──────────────────────────────────────────────
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACCESS_JSON = os.path.join(REPO_DIR, "terraform", "access.json")


def pending_prs():
    try:
        out = run(["gh", "pr", "list", "--repo", REPO, "--state", "open",
                   "--json", "number,title,url,author,headRefName"])
        return json.loads(out.stdout)
    except Exception:
        return []


def access_matrix():
    try:
        with open(ACCESS_JSON) as f:
            return json.load(f)
    except Exception:
        return {}


def merge_and_apply(num):
    """PR 머지 → main pull → terraform apply (승인=즉시 권한부여)."""
    try:
        run(["gh", "pr", "merge", str(num), "--repo", REPO, "--merge", "--delete-branch"])
        run(["git", "fetch", "origin", "main"], cwd=REPO_DIR)
        run(["git", "checkout", "main"], cwd=REPO_DIR)
        run(["git", "pull", "--ff-only", "origin", "main"], cwd=REPO_DIR)
        run(["terraform", "apply", "-auto-approve"], cwd=os.path.join(REPO_DIR, "terraform"))
        return None
    except subprocess.CalledProcessError as e:
        return (e.stderr or e.stdout or str(e))


def render_admin(msg=""):
    m = access_matrix()
    prs = pending_prs()
    # 권한 매트릭스
    rows = ""
    for u in USERS:
        cells = ""
        for t in TARGETS:
            ok = t in m.get(u, [])
            dot = ('<span class="text-emerald-400">●</span>' if ok
                   else '<span class="text-slate-600">○</span>')
            cells += f'<td class="text-center py-2">{dot}</td>'
        rows += f'<tr class="border-t border-slate-800"><td class="py-2 pr-3 font-medium">{u}</td>{cells}</tr>'
    heads = "".join(f'<th class="px-2 py-2 font-medium text-slate-400 text-[11px]">{t.replace("-target","")}</th>' for t in TARGETS)
    # 신청 PR 목록
    if prs:
        items = ""
        for p in prs:
            items += (
                f'<div class="flex items-center gap-3 rounded-xl border border-slate-700/60 bg-slate-900/60 px-4 py-3">'
                f'<div class="flex-1 min-w-0"><div class="text-sm font-medium truncate">{html.escape(p["title"])}</div>'
                f'<div class="text-[12px] text-slate-500">#{p["number"]} · {html.escape(p["author"]["login"])} · '
                f'<a class="text-sky-400 underline" href="{html.escape(p["url"])}" target="_blank">PR 보기</a></div></div>'
                f'<form method="POST" action="/admin/merge"><input type="hidden" name="num" value="{p["number"]}">'
                f'<button class="flex items-center gap-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-semibold px-3 py-2 transition">'
                f'<i data-lucide="check" class="w-4 h-4"></i>승인 &amp; 적용</button></form></div>')
        prs_html = f'<div class="space-y-2">{items}</div>'
    else:
        prs_html = '<div class="text-slate-500 text-sm py-6 text-center">대기 중인 신청이 없습니다.</div>'

    return (ADMIN.replace("__MSG__", msg)
                 .replace("__PRS__", prs_html)
                 .replace("__HEADS__", heads)
                 .replace("__ROWS__", rows))


class H(BaseHTTPRequestHandler):
    def _send(self, body, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body.encode("utf-8"))

    def _redirect(self, loc):
        self.send_response(303)
        self.send_header("Location", loc)
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/admin"):
            self._send(render_admin())
        else:
            self._send(render())

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        form = parse_qs(self.rfile.read(n).decode("utf-8"))
        g = lambda k: form.get(k, [""])[0]
        if self.path == "/admin/merge":
            err = merge_and_apply(g("num"))
            msg = (msg_err(err) if err else
                   '<div class="mt-4 rounded-xl border border-emerald-500/40 bg-emerald-500/10 p-3.5 text-[13px] text-emerald-200">✅ 승인 &amp; 적용 완료 — 권한이 부여되었습니다.</div>')
            self._send(render_admin(msg))
        else:
            url, err = create_pr(g("requester"), g("target"), g("reason"), g("duration"))
            self._send(render(msg_err(err) if err else msg_ok(url)))

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print(f"Boundary 신청 포털: http://127.0.0.1:{PORT}")
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
