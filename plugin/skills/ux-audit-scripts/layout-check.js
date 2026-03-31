// Layout and element checker — inject via evaluate_script
// Checks: touch target sizes, heading hierarchy, form labels, horizontal scroll

(function() {
  var findings = [];

  // 1. Touch target check (WCAG 2.5.8 — minimum 44x44px for interactive elements)
  var interactiveSelectors = 'a, button, input, select, textarea, [role="button"], [role="link"], [role="checkbox"], [role="radio"], [role="tab"], [onclick]';
  var interactive = document.querySelectorAll(interactiveSelectors);
  interactive.forEach(function(el) {
    var style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden') return;
    var rect = el.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0 && (rect.width < 44 || rect.height < 44)) {
      findings.push({
        type: 'touch-target',
        severity: rect.width < 24 || rect.height < 24 ? 'critical' : 'major',
        element: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className ? '.' + el.className.split(' ')[0] : ''),
        text: (el.textContent || el.value || el.getAttribute('aria-label') || '').trim().substring(0, 50),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
        required: '44x44',
        selector: el.id ? '#' + el.id : (el.className ? '.' + el.className.split(' ').join('.') : el.tagName.toLowerCase())
      });
    }
  });

  // 2. Heading hierarchy check (WCAG 1.3.1 — headings must not skip levels)
  var headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
  var headingLevels = [];
  var headingIssues = [];
  var h1Count = 0;
  headings.forEach(function(h) {
    var style = window.getComputedStyle(h);
    if (style.display === 'none') return;
    var level = parseInt(h.tagName[1]);
    headingLevels.push({ level: level, text: h.textContent.trim().substring(0, 60) });
    if (level === 1) h1Count++;
  });
  // Check for skipped levels
  for (var i = 1; i < headingLevels.length; i++) {
    var gap = headingLevels[i].level - headingLevels[i-1].level;
    if (gap > 1) {
      headingIssues.push({
        type: 'heading-skip',
        severity: 'major',
        from: 'h' + headingLevels[i-1].level + ': ' + headingLevels[i-1].text,
        to: 'h' + headingLevels[i].level + ': ' + headingLevels[i].text,
        skipped: 'h' + (headingLevels[i-1].level + 1)
      });
    }
  }
  if (h1Count === 0 && headingLevels.length > 0) {
    headingIssues.push({ type: 'heading-no-h1', severity: 'major', detail: 'Page has headings but no h1' });
  }
  if (h1Count > 1) {
    headingIssues.push({ type: 'heading-multiple-h1', severity: 'minor', detail: h1Count + ' h1 elements found (typically should be 1)' });
  }

  // 3. Form label check (WCAG 1.3.1, 4.1.2 — inputs must have labels)
  var inputs = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), select, textarea');
  var labelIssues = [];
  inputs.forEach(function(input) {
    var style = window.getComputedStyle(input);
    if (style.display === 'none') return;
    var hasLabel = false;
    // Check for associated <label>
    if (input.id) {
      hasLabel = !!document.querySelector('label[for="' + input.id + '"]');
    }
    // Check for wrapping <label>
    if (!hasLabel) {
      hasLabel = !!input.closest('label');
    }
    // Check for aria-label or aria-labelledby
    if (!hasLabel) {
      hasLabel = !!(input.getAttribute('aria-label') || input.getAttribute('aria-labelledby'));
    }
    // Check for placeholder (not ideal but counts as accessible name)
    if (!hasLabel) {
      hasLabel = !!input.getAttribute('placeholder');
    }
    if (!hasLabel) {
      labelIssues.push({
        type: 'missing-label',
        severity: 'critical',
        element: input.tagName.toLowerCase() + '[type="' + (input.type || 'text') + '"]',
        name: input.name || input.id || '(unnamed)',
        selector: input.id ? '#' + input.id : (input.name ? '[name="' + input.name + '"]' : input.tagName.toLowerCase())
      });
    }
  });

  // 4. Image alt text check
  var images = document.querySelectorAll('img');
  var altIssues = [];
  images.forEach(function(img) {
    var style = window.getComputedStyle(img);
    if (style.display === 'none') return;
    if (!img.hasAttribute('alt')) {
      altIssues.push({
        type: 'missing-alt',
        severity: 'critical',
        src: img.src.substring(0, 100),
        selector: img.id ? '#' + img.id : (img.className ? 'img.' + img.className.split(' ')[0] : 'img')
      });
    }
  });

  // 5. Horizontal scroll check
  var hasHorizontalScroll = document.documentElement.scrollWidth > document.documentElement.clientWidth;

  // 6. html lang attribute
  var hasLang = !!document.documentElement.getAttribute('lang');

  return {
    touchTargets: { failures: findings.filter(function(f) { return f.type === 'touch-target'; }), total: interactive.length },
    headings: { issues: headingIssues, levels: headingLevels, h1Count: h1Count },
    formLabels: { issues: labelIssues, totalInputs: inputs.length },
    imageAlts: { issues: altIssues, totalImages: images.length },
    horizontalScroll: hasHorizontalScroll,
    htmlLang: hasLang,
    timestamp: new Date().toISOString()
  };
})();
