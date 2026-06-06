#!/usr/bin/env python3
"""docs 의 .md 를 다크테마 .html 로 변환. 사용: python3 build-html.py <md파일> <제목>"""
import sys, markdown

TEMPLATE = """<!DOCTYPE html>
<html lang="ko"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>{title}</title>
<style>
:root{{--bg:#0f1117;--panel:#171a23;--line:#2c3142;--txt:#e6e9f0;--dim:#9aa3b2;
--accent:#7c5cff;--green:#34d399;--red:#f87171;--blue:#60a5fa}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--txt);line-height:1.7;
font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Apple SD Gothic Neo",sans-serif}}
.wrap{{max-width:900px;margin:0 auto;padding:40px 24px 90px}}
h1{{font-size:30px;margin:8px 0 18px;line-height:1.25}}
h1+blockquote{{margin-top:-6px}}
h2{{font-size:22px;margin:42px 0 14px;padding:10px 0 6px;border-bottom:2px solid var(--accent)}}
h3{{font-size:17px;margin:24px 0 8px;color:var(--blue)}}
p,li{{margin:7px 0}}
hr{{border:none;border-top:1px solid var(--line);margin:34px 0}}
code{{background:#0b0d13;border:1px solid var(--line);border-radius:5px;padding:1px 6px;
font-size:13px;font-family:"SF Mono",Menlo,monospace}}
pre{{background:#0b0d13;border:1px solid var(--line);border-radius:10px;padding:14px 16px;overflow:auto}}
pre code{{background:none;border:none;padding:0;font-size:13px;line-height:1.55}}
blockquote{{margin:12px 0;padding:10px 16px;border-left:3px solid var(--accent);
background:rgba(124,92,255,.07);border-radius:0 8px 8px 0;color:var(--dim)}}
blockquote p{{margin:4px 0}}
table{{width:100%;border-collapse:collapse;font-size:14px;margin:14px 0;
background:var(--panel);border:1px solid var(--line);border-radius:10px;overflow:hidden}}
th,td{{text-align:left;padding:9px 12px;border-bottom:1px solid var(--line)}}
th{{color:var(--dim);font-size:12px;text-transform:uppercase;letter-spacing:.4px;background:#12141c}}
tr:last-child td{{border-bottom:none}}
a{{color:var(--blue)}}
ul,ol{{padding-left:22px}}
strong{{color:#fff}}
</style></head>
<body><div class="wrap">
{body}
</div></body></html>
"""

src, title = sys.argv[1], sys.argv[2]
md = open(src, encoding="utf-8").read()
body = markdown.markdown(md, extensions=["tables", "fenced_code", "toc", "sane_lists"])
out = src.rsplit(".", 1)[0] + ".html"
open(out, "w", encoding="utf-8").write(TEMPLATE.format(title=title, body=body))
print("wrote", out)
