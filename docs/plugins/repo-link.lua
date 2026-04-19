-- Inject a "View on GitHub" badge into the page header.
-- Star and fork counts are filled in client-side from the GitHub API
-- by scripts/repo-stats.js.
--
-- Configuration:
--   [widgets.repo-link]
--     widget = "repo-link"
--     url      = "https://github.com/owner/repo"   (required)
--     label    = "owner/repo"                       (optional; auto-derived from URL)
--     selector = "header.site-header"               (optional; default mount point)
--
-- The link's href is left as the absolute GitHub URL on purpose so the
-- urls.lua plugin (which only relativizes /-rooted paths) won't touch it.

url = config["url"]
if not url then Plugin.fail("repo-link: missing 'url' option") end

selector = config["selector"]
if not selector then selector = "header.site-header" end

label = config["label"]
if not label then
  label = Regex.replace(url, "^https?://", "")
  label = Regex.replace(label, "^github\\.com/", "")
  label = Regex.replace(label, "/$", "")
  label = Regex.replace(label, "\\.git$", "")
end

-- GitHub Octicons (MIT, 16x16). Inline so no external icon-font load.
octocat = "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"

star = "M8 .25a.75.75 0 0 1 .673.418l1.882 3.815 4.21.612a.75.75 0 0 1 .416 1.279l-3.046 2.97.719 4.192a.75.75 0 0 1-1.088.791L8 12.347l-3.766 1.98a.75.75 0 0 1-1.088-.79l.72-4.194L.818 6.374a.75.75 0 0 1 .416-1.28l4.21-.611L7.327.668A.75.75 0 0 1 8 .25z"

fork = "M5 5.372v.878c0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75v-.878a2.25 2.25 0 1 1 1.5 0v.878a2.25 2.25 0 0 1-2.25 2.25h-1.5v2.128a2.251 2.251 0 1 1-1.5 0V8.5h-1.5A2.25 2.25 0 0 1 3.5 6.25v-.878a2.25 2.25 0 1 1 1.5 0zM5 3.25a.75.75 0 1 0-1.5 0 .75.75 0 0 0 1.5 0zm6.75.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5zm-3 8.75a.75.75 0 1 0-1.5 0 .75.75 0 0 0 1.5 0z"

a_open = format(
  '<a class="repo-link" href="%s" target="_blank" rel="noopener" data-repo-url="%s" aria-label="View on GitHub">',
  url, url)

icon = format(
  '<svg class="repo-icon" viewBox="0 0 16 16" aria-hidden="true"><path fill-rule="evenodd" d="%s"/></svg>',
  octocat)

stars = format(
  '<span class="repo-stat" title="Stars"><svg class="repo-stat-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="%s"/></svg><span class="repo-stat-count" data-repo-stat="stars">…</span></span>',
  star)

forks = format(
  '<span class="repo-stat" title="Forks"><svg class="repo-stat-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="%s"/></svg><span class="repo-stat-count" data-repo-stat="forks">…</span></span>',
  fork)

text = format(
  '<span class="repo-text"><span class="repo-name">%s</span><span class="repo-stats">%s%s</span></span>',
  label, stars, forks)

html = a_open .. icon .. text .. "</a>"

container = HTML.select_one(page, selector)
if container then
  HTML.append_child(container, HTML.parse(html))
end
