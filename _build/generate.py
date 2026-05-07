#!/usr/bin/env python3
"""Generate dynamic sections of index.html and research/index.html from data files."""

import glob
import json
import re
import subprocess
from datetime import datetime, timezone
from email.utils import format_datetime

SITE_URL = 'https://wolfcukier.com'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

LINK_ICONS = {
    'pdf':   'fas fa-file-lines',
    'code':  'fab fa-github',
    'arxiv': 'ai ai-arxiv',
}

def link_icon(label):
    return LINK_ICONS.get(label.lower(), 'fas fa-link')


def splice(filepath, marker, inner_html):
    with open(filepath) as f:
        content = f.read()
    begin = f'<!-- BEGIN_{marker} -->'
    end   = f'<!-- END_{marker} -->'
    replacement = begin + '\n' + inner_html + '\n      ' + end
    content = re.sub(
        begin + r'.*?' + end,
        replacement,
        content,
        flags=re.DOTALL,
    )
    with open(filepath, 'w') as f:
        f.write(content)


# ---------------------------------------------------------------------------
# About
# ---------------------------------------------------------------------------

def build_about():
    with open('_data/about.md') as f:
        md = f.read()
    result = subprocess.run(
        ['pandoc', '--from=markdown', '--to=html5'],
        input=md, capture_output=True, text=True, check=True,
    )
    # Indent each line to match surrounding HTML
    lines = result.stdout.strip().splitlines()
    indented = '\n'.join('        ' + line for line in lines)
    splice('index.html', 'ABOUT', indented)
    print('rebuilt: about section')


# ---------------------------------------------------------------------------
# Books
# ---------------------------------------------------------------------------

def build_books():
    with open('_data/books.json') as f:
        books = json.load(f)
    items = '\n'.join(
        f'          <div class="book-item"><em>{b["title"]}</em><small>{b["author"]}</small></div>'
        for b in books
    )
    splice('index.html', 'BOOKS', items)
    print('rebuilt: books section')


# ---------------------------------------------------------------------------
# Research
# ---------------------------------------------------------------------------

def build_research():
    with open('_data/research.json') as f:
        papers = sorted(json.load(f), key=lambda p: p['year'], reverse=True)

    def make_rows(papers, img_prefix=''):
        rows = []
        for p in papers:
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
                + img_html
                + f'            <div>\n'
                  f'              <div class="row-title"><a href="{p["url"]}">{p["title"]}</a></div>\n'
                  f'              <div class="row-venue">{p["citation"]}<em> · {p["journal"]}</em></div>\n'
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
                f'        <div class="section-header"><div class="section-rule"><img class="section-planet" src="{img_prefix}planet_logo.svg" alt=""></div><h2>{heading}</h2></div>\n'
                f'        <div class="research-grid">\n\n'
                + make_rows(group, img_prefix) + '\n\n'
                f'        </div>\n'
                f'      </section>'
            )
        return '\n\n'.join(sections)

    def make_featured_rows(papers, img_prefix=''):
        rows = []
        for p in [x for x in papers if x.get('featured')]:
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
                + img_html
                + f'            <div>\n'
                  f'              <div class="row-title"><a href="{p["url"]}">{p["title"]}</a></div>\n'
                  f'              <div class="row-venue">{p["citation"]}<em> · {p["journal"]}</em></div>\n'
                  f'              <div class="row-desc">{p["description"]}</div>\n'
                  f'              <div class="row-links">\n'
                  f'{links_html}\n'
                  f'              </div>\n'
                  f'            </div>\n'
                  f'          </div>'
            )
        return '\n\n'.join(rows)

    # index.html — featured papers stub
    stub = (
        '      <div class="research-grid">\n\n'
        + make_featured_rows(papers, img_prefix='images/') + '\n\n'
        '      </div>'
    )
    splice('index.html', 'RESEARCH', stub)

    # research/index.html — full listing
    splice('research/index.html', 'RESEARCH', full_sections(papers, img_prefix='../images/'))

    print('rebuilt: research sections')


# ---------------------------------------------------------------------------
# RSS feed
# ---------------------------------------------------------------------------

def _parse_post(path):
    with open(path) as f:
        text = f.read()
    # Split on YAML frontmatter delimiters
    parts = re.split(r'^---\s*$', text, maxsplit=2, flags=re.MULTILINE)
    if len(parts) < 3:
        return None
    fm_raw, body = parts[1], parts[2]

    def fm_get(key):
        m = re.search(rf"^{key}:\s*['\"]?(.+?)['\"]?\s*$", fm_raw, re.MULTILINE)
        return m.group(1) if m else ''

    title     = fm_get('title')
    date_str  = fm_get('date')
    permalink = fm_get('permalink').strip('/')

    if not (title and date_str):
        return None

    url = f'{SITE_URL}/{permalink}/' if permalink else None

    # RFC 822 date for RSS
    dt = datetime.strptime(date_str.strip(), '%Y-%m-%d').replace(tzinfo=timezone.utc)
    pub_date = format_datetime(dt)

    # Use first paragraph as description
    first_para = next((p.strip() for p in body.strip().split('\n\n') if p.strip() and not p.strip().startswith('#')), '')
    result = subprocess.run(
        ['pandoc', '--from=markdown', '--to=html5'],
        input=first_para, capture_output=True, text=True, check=True,
    )
    content_html = result.stdout.strip()

    return {'title': title, 'url': url, 'pub_date': pub_date, 'dt': dt, 'content': content_html}


def build_rss():
    posts = []
    for path in sorted(glob.glob('_posts/*.md'), reverse=True):
        post = _parse_post(path)
        if post and post['url']:
            posts.append(post)

    now_rfc822 = format_datetime(datetime.now(timezone.utc))

    items = []
    for p in posts:
        items.append(
            f'    <item>\n'
            f'      <title>{p["title"]}</title>\n'
            f'      <link>{p["url"]}</link>\n'
            f'      <guid>{p["url"]}</guid>\n'
            f'      <pubDate>{p["pub_date"]}</pubDate>\n'
            f'      <description><![CDATA[{p["content"]}]]></description>\n'
            f'    </item>'
        )

    feed = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n'
        '  <channel>\n'
        '    <title>Wolf Cukier</title>\n'
        f'    <link>{SITE_URL}/blog/</link>\n'
        f'    <atom:link href="{SITE_URL}/blog/feed.xml" rel="self" type="application/rss+xml"/>\n'
        '    <description>Blog posts by Wolf Cukier</description>\n'
        f'    <lastBuildDate>{now_rfc822}</lastBuildDate>\n'
        '\n'
        + '\n\n'.join(items) + '\n'
        '  </channel>\n'
        '</rss>\n'
    )

    with open('blog/feed.xml', 'w') as f:
        f.write(feed)
    print('rebuilt: blog/feed.xml')


# ---------------------------------------------------------------------------

if __name__ == '__main__':
    build_about()
    build_books()
    build_research()
    build_rss()
