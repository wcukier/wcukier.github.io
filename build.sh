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
  <link rel="icon" type="image/svg+xml" href="../images/planet_logo.svg">
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Courier+Prime:ital,wght@0,400;0,700;1,400&display=swap">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
  <link rel="stylesheet" href="../css/main.css">
  <link rel="alternate" type="application/rss+xml" title="Wolf Cukier" href="/blog/feed.xml">
</head>
<body>
  <nav>
    <div class="nav-inner">
      <a class="nav-name" href="../">Wolf Cukier</a>
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
        <div class="section-header"><div class="section-rule"><img class="section-planet" src="../images/planet_logo.svg" alt=""></div><h2>Posts</h2></div>
        <a class="rss-link" href="/blog/feed.xml">RSS Feed</a>
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
    <span>Wolf Cukier</span>
    <span>wolfcukier.com</span>
    <span><a href="mailto:wcukier@uchicago.edu" style="color:inherit;text-decoration:none;">wcukier@uchicago.edu</a></span>
  </footer>
</body>
</html>
HTMLEOF

echo "rebuilt: blog/index.html"

# Regenerate about, books, and research sections from data files
python3 _build/generate.py
