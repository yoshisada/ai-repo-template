// axe-core injection script for use with /chrome evaluate_script
// Injects axe-core from CDN, runs a full WCAG 2.1 AA audit, returns results
//
// Usage in ux-evaluator agent:
//   1. Read this file
//   2. Pass its contents to evaluate_script
//   3. Wait for window.__axeResults to be populated
//   4. Read results via evaluate_script: "return window.__axeResults"

(function() {
  return new Promise(function(resolve) {
    // Check if axe is already loaded
    if (typeof window.axe !== 'undefined') {
      window.axe.run({
        runOnly: {
          type: 'tag',
          values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'best-practice']
        },
        resultTypes: ['violations', 'incomplete']
      }).then(function(results) {
        var summary = {
          violations: results.violations.map(function(v) {
            return {
              id: v.id,
              impact: v.impact,
              description: v.description,
              help: v.help,
              helpUrl: v.helpUrl,
              tags: v.tags,
              nodes: v.nodes.map(function(n) {
                return {
                  html: n.html.substring(0, 200),
                  target: n.target,
                  failureSummary: n.failureSummary
                };
              })
            };
          }),
          incomplete: results.incomplete.length,
          passes: results.passes.length,
          violationCount: results.violations.length,
          timestamp: new Date().toISOString()
        };
        window.__axeResults = summary;
        resolve(summary);
      });
      return;
    }

    // Inject axe-core from CDN
    var script = document.createElement('script');
    script.src = 'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.10.0/axe.min.js';
    script.crossOrigin = 'anonymous';
    script.onload = function() {
      window.axe.run({
        runOnly: {
          type: 'tag',
          values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'best-practice']
        },
        resultTypes: ['violations', 'incomplete']
      }).then(function(results) {
        var summary = {
          violations: results.violations.map(function(v) {
            return {
              id: v.id,
              impact: v.impact,
              description: v.description,
              help: v.help,
              helpUrl: v.helpUrl,
              tags: v.tags,
              nodes: v.nodes.map(function(n) {
                return {
                  html: n.html.substring(0, 200),
                  target: n.target,
                  failureSummary: n.failureSummary
                };
              })
            };
          }),
          incomplete: results.incomplete.length,
          passes: results.passes.length,
          violationCount: results.violations.length,
          timestamp: new Date().toISOString()
        };
        window.__axeResults = summary;
        resolve(summary);
      });
    };
    script.onerror = function() {
      var error = { error: 'Failed to load axe-core from CDN', timestamp: new Date().toISOString() };
      window.__axeResults = error;
      resolve(error);
    };
    document.head.appendChild(script);
  });
})();
