{{flutter_js}}
{{flutter_build_config}}

// Every deploy stamps its build id (index.html -> window.__BUILD_ID__). Putting it
// on the entrypoint URL makes a browser that still holds the previous main.dart.js
// in its HTTP cache fetch the new file instead of reusing the old one.
(function () {
  var build = window.__BUILD_ID__ || '';
  if (!build) return;
  var builds = (_flutter.buildConfig && _flutter.buildConfig.builds) || [];
  builds.forEach(function (b) {
    if (b.mainJsPath) b.mainJsPath += '?v=' + build;
  });
})();

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
