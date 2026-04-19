-- Build the sidebar navigation by iterating over the global site_index
-- and grouping entries by their `section` custom field.

tmpl = config["nav_template"]
selector = config["nav_selector"]

if not tmpl then Plugin.fail("Missing nav_template option") end
if not selector then Plugin.fail("Missing nav_selector option") end

env = {}
env["entries"] = site_index

rendered = HTML.parse(String.render_template(tmpl, env))
container = HTML.select_one(page, selector)
if container then
  HTML.append_child(container, rendered)
end
