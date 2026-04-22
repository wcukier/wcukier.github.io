#!/usr/bin/env bash
set -euo pipefail

POSTS_SRC="_posts"
TEMPLATE="templates/post.html"
RESEARCH_SRC="_research_pages"
RESEARCH_TEMPLATE="templates/research_page.html"

for src in "$RESEARCH_SRC"/*.md; do
  [ -f "$src" ] || continue
  slug=$(basename "$src" .md)
  out="research/${slug}/index.html"
  mkdir -p "$(dirname "$out")"
  pandoc "$src" \
    --template="$RESEARCH_TEMPLATE" \
    --from=markdown \
    --to=html5 \
    --output="$out"
  echo "built: $out"
done

for src in "$POSTS_SRC"/*.md; do
  [ -f "$src" ] || continue
  filename=$(basename "$src" .md)

  # Read permalink from frontmatter; fall back to blog/posts/{slug}.html
  permalink=$(python3 -c "
import re, sys
for line in open('$src'):
    m = re.match(r'^permalink:\s*(.+?)\s*$', line)
    if m: print(m.group(1).strip('/\"\\'')); break
")

  if [ -n "$permalink" ]; then
    out="${permalink}/index.html"
  else
    out="blog/posts/${filename}.html"
  fi

  # Calculate csspath: one ../ per directory level in the output path
  csspath=$(python3 -c "
import os
depth = len(os.path.dirname('$out').split('/'))
print('../' * depth)
")

  mkdir -p "$(dirname "$out")"
  pandoc "$src" \
    --template="$TEMPLATE" \
    --from=markdown \
    --to=html5 \
    --variable "csspath=${csspath}" \
    --output="$out"
  echo "built: $out"
done

# Regenerate blog/index.html from post metadata
cat > blog/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Blog · Wolf Cukier</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
  <link rel="stylesheet" href="../css/main.css">
</head>
<body>
  <nav>
    <div class="nav-inner">
      <a class="nav-name" href="../">wolf cukier</a>
      <ul class="nav-links">
        <li><a href="../research/">Research</a></li>
        <li><a href="../blog/" class="active">Blog</a></li>
        <li><a href="../files/cv.pdf">CV</a></li>
      </ul>
    </div>
  </nav>
  <div class="page-wrapper">
    <main class="content">
      <section class="section">
        <div class="section-header"><h2>Posts</h2></div>
        <ul class="post-list">
HTMLEOF

# Append one list item per post, newest first
for src in $(ls -r "$POSTS_SRC"/*.md 2>/dev/null); do
  [ -f "$src" ] || continue
  filename=$(basename "$src" .md)
  title=$(python3 -c "
import re
for line in open('$src'):
    m = re.match(r\"^title:\\s*['\\\"]?(.+?)['\\\"]?\\s*$\", line)
    if m: print(m.group(1)); break
")
  date=$(python3 -c "
import re
for line in open('$src'):
    m = re.match(r'^date:\\s*(.+?)\\s*$', line)
    if m: print(m.group(1)); break
")
  permalink=$(python3 -c "
import re
for line in open('$src'):
    m = re.match(r'^permalink:\\s*(.+?)\\s*$', line)
    if m: print(m.group(1).strip('/\"\\'')); break
")
  if [ -n "$permalink" ]; then
    url="../${permalink}/"
  else
    url="blog/posts/${filename}.html"
  fi
  cat >> blog/index.html <<ITEMEOF
          <li class="post-item">
            <span class="post-title"><a href="${url}">${title}</a></span>
            <span class="post-date">${date}</span>
          </li>
ITEMEOF
done

cat >> blog/index.html <<'HTMLEOF'
        </ul>
      </section>
    </main>
  </div>
  <footer>
    <span>Wolf Cukier · wolfcukier.com</span>
    <span>wcukier@uchicago.edu</span>
  </footer>
</body>
</html>
HTMLEOF

echo "rebuilt: blog/index.html"

# Regenerate research sections in research.html and index.html from _data/research.json
python3 - <<'PYEOF'
import json, re

with open('_data/research.json') as f:
    papers = sorted(json.load(f), key=lambda p: p['year'], reverse=True)

LINK_ICONS = {
    'pdf':  'fas fa-file-pdf',
    'code': 'fab fa-github',
    'arxiv': 'ai ai-arxiv',
}

def link_icon(label):
    return LINK_ICONS.get(label.lower(), 'fas fa-link')

def make_rows(papers, img_prefix=''):
    rows = []
    for i, p in enumerate(papers, 1):
        num = f'{i:02d}'
        links_html = '\n'.join(
            f'              <a href="{l["url"]}"><i class="{link_icon(l["label"])}"></i> {l["label"]}</a>'
            for l in p['links']
        )
        img = p.get('image', '')
        if img and img_prefix:
            row_class = 'research-row has-image'
            img_html = f'            <div class="row-img"><img src="{img_prefix}{img}" alt=""></div>\n'
        else:
            row_class = 'research-row'
            img_html = ''
        rows.append(
            f'          <div class="{row_class}">\n'
            + img_html +
            f'            <div>\n'
            f'              <div class="row-title"><a href="{p["url"]}">{p["title"]}</a></div>\n'
            f'              <div class="row-venue">{p["citation"]} · <em>{p["journal"]}</em></div>\n'
            f'              <div class="row-desc">{p["description"]}</div>\n'
            f'            </div>\n'
            f'            <div class="row-meta">\n'
            f'              <div class="row-year">{p["year"]}</div>\n'
            f'              <div class="row-links">\n'
            f'{links_html}\n'
            f'              </div>\n'
            f'            </div>\n'
            f'          </div>'
        )
    return '\n\n'.join(rows)

def full_sections(papers, img_prefix=''):
    first = [p for p in papers if p.get('first_author')]
    other = [p for p in papers if not p.get('first_author')]
    sections = []
    for heading, group in [('First Author', first), ('Other Publications', other)]:
        if not group:
            continue
        sections.append(
            f'      <section class="section">\n'
            f'        <div class="section-header"><h2>{heading}</h2></div>\n'
            f'        <div class="research-grid">\n\n'
            + make_rows(group, img_prefix) + '\n\n'
            f'        </div>\n'
            f'      </section>'
        )
    return '\n\n'.join(sections)

def make_featured_rows(papers, img_prefix=''):
    rows = []
    for i, p in enumerate([x for x in papers if x.get('featured')], 1):
        num = f'{i:02d}'
        img = p.get('image', '')
        img_html = (
            f'            <div class="row-img"><img src="{img_prefix}{img}" alt=""></div>\n'
            if img and img_prefix else ''
        )
        links_html = '\n'.join(
            f'              <a href="{l["url"]}"><i class="{link_icon(l["label"])}"></i> {l["label"]}</a>'
            for l in p.get('links', [])
        )
        rows.append(
            f'          <div class="featured-row">\n'
            + img_html +
            f'            <div>\n'
            f'              <div class="row-title"><a href="{p["url"]}">{p["title"]}</a></div>\n'
            f'              <div class="row-venue">{p["citation"]} · <em>{p["journal"]}</em> · {p["year"]}</div>\n'
            f'              <div class="row-desc">{p["description"]}</div>\n'
            f'              <div class="row-links">\n'
            f'{links_html}\n'
            f'              </div>\n'
            f'            </div>\n'
            f'          </div>'
        )
    return '\n\n'.join(rows)

def stub_section(papers):
    return (
        '      <div class="research-grid">\n\n'
        + make_featured_rows(papers, img_prefix='images/') + '\n\n'
        '      </div>'
    )

def splice(filepath, inner_html):
    with open(filepath) as f:
        content = f.read()
    replacement = '<!-- BEGIN_RESEARCH -->\n' + inner_html + '\n      <!-- END_RESEARCH -->'
    content = re.sub(
        r'<!-- BEGIN_RESEARCH -->.*?<!-- END_RESEARCH -->',
        replacement,
        content,
        flags=re.DOTALL
    )
    with open(filepath, 'w') as f:
        f.write(content)

splice('research/index.html', full_sections(papers, img_prefix='../images/'))
splice('index.html', stub_section(papers))
print('rebuilt: research sections')
PYEOF
