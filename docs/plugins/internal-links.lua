-- Rewrite same-site *.md links to clean URLs.
--   architecture/overview.md         -> architecture/overview/
--   adr/0001-foo.md                  -> adr/0001-foo/
--   adr/README.md                    -> adr/
--   foo.md#section                   -> foo/#section
--   ../README.md                     -> left untouched
--   https://example.com/x.md         -> left untouched

links = HTML.select(page, "a[href]")
n = size(links)

i = 1
while i <= n do
  link = links[i]
  href = HTML.get_attribute(link, "href")

  skip = true
  if href then
    skip = false
    if not Regex.match(href, "\\.md($|#)") then skip = true end
    if Regex.match(href, "^[a-z]+://")     then skip = true end
    if Regex.match(href, "^mailto:")       then skip = true end
    if Regex.match(href, "^#")             then skip = true end
    if Regex.match(href, "^\\.\\./")       then skip = true end
  end

  if not skip then
    -- Split path and fragment manually (Regex backrefs in replace are not supported)
    if Regex.match(href, "#") then
      path_part = Regex.replace(href, "#.*$", "")
      frag_match = Regex.find_all(href, "#.*$")
      fragment = frag_match[1]
    else
      path_part = href
      fragment = ""
    end

    -- README.md -> "" (i.e. the section index)
    new_path = Regex.replace(path_part, "README\\.md$", "")
    -- Other .md -> /
    new_path = Regex.replace(new_path, "\\.md$", "/")

    if new_path == "" then new_path = "./" end

    HTML.set_attribute(link, "href", new_path .. fragment)
  end

  i = i + 1
end
