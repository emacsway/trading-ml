// Populate the repo-link badge with live star/fork counts from the
// GitHub REST API. Cached for the session to avoid hammering the API.
// Fails silently — the placeholder character stays if the request fails
// (e.g. rate-limited, offline, or fetch blocked under file://).

(function () {
  var link = document.querySelector('.repo-link[data-repo-url]');
  if (!link) return;

  var url = link.getAttribute('data-repo-url');
  var m = url.match(/github\.com\/([^\/]+)\/([^\/?#]+)/);
  if (!m) return;

  var owner = m[1];
  var repo = m[2].replace(/\.git$/, '');
  var key = 'repo-stats:' + owner + '/' + repo;

  var fmt = function (n) {
    if (n >= 100000) return Math.round(n / 1000) + 'k';
    if (n >= 10000)  return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    if (n >= 1000)   return (n / 1000).toFixed(1) + 'k';
    return String(n);
  };

  var apply = function (data) {
    var s = link.querySelector('[data-repo-stat="stars"]');
    var f = link.querySelector('[data-repo-stat="forks"]');
    if (s && typeof data.stargazers_count === 'number') s.textContent = fmt(data.stargazers_count);
    if (f && typeof data.forks_count === 'number')      f.textContent = fmt(data.forks_count);
  };

  try {
    var cached = JSON.parse(sessionStorage.getItem(key) || 'null');
    if (cached) apply(cached);
  } catch (e) { /* ignore */ }

  fetch('https://api.github.com/repos/' + owner + '/' + repo, {
    headers: { 'Accept': 'application/vnd.github+json' }
  })
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (d) {
      if (!d) return;
      apply(d);
      try {
        sessionStorage.setItem(key, JSON.stringify({
          stargazers_count: d.stargazers_count,
          forks_count: d.forks_count
        }));
      } catch (e) { /* ignore */ }
    })
    .catch(function () { /* ignore */ });
})();
