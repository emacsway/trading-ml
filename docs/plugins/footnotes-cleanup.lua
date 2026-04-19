-- Remove the footnotes container from pages that have no footnotes.

if not Table.has_key(config, "footnote_link_selector") then
  Plugin.fail("Please specify footnote_link_selector")
end

if not Table.has_key(config, "footnotes_container_selector") then
  Plugin.fail("Please specify footnotes_container_selector")
end

footnotes = HTML.select(page, config["footnote_link_selector"])

if size(footnotes) == 0 then
  container = HTML.select_one(page, config["footnotes_container_selector"])
  if container then
    HTML.delete(container)
  end
end
