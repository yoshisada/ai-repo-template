// Contrast ratio checker — inject via evaluate_script
// Finds all text elements, computes WCAG contrast ratios against their backgrounds
// Returns an array of elements that fail WCAG 2.1 AA contrast requirements

(function() {
  function luminance(r, g, b) {
    var a = [r, g, b].map(function(v) {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    });
    return a[0] * 0.2126 + a[1] * 0.7152 + a[2] * 0.0722;
  }

  function parseColor(color) {
    if (!color || color === 'transparent' || color === 'rgba(0, 0, 0, 0)') return null;
    var match = color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (match) return { r: parseInt(match[1]), g: parseInt(match[2]), b: parseInt(match[3]) };
    return null;
  }

  function getEffectiveBackground(el) {
    var current = el;
    while (current && current !== document.documentElement) {
      var bg = window.getComputedStyle(current).backgroundColor;
      var parsed = parseColor(bg);
      if (parsed && (parsed.r !== 0 || parsed.g !== 0 || parsed.b !== 0 || bg.indexOf('rgba') === -1)) {
        return parsed;
      }
      current = current.parentElement;
    }
    return { r: 255, g: 255, b: 255 }; // default white
  }

  function contrastRatio(fg, bg) {
    var l1 = luminance(fg.r, fg.g, fg.b);
    var l2 = luminance(bg.r, bg.g, bg.b);
    var lighter = Math.max(l1, l2);
    var darker = Math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  var failures = [];
  var textElements = document.querySelectorAll('p, span, a, button, label, h1, h2, h3, h4, h5, h6, li, td, th, input, textarea, select, div, section');

  textElements.forEach(function(el) {
    // Skip hidden elements
    var style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return;

    // Skip elements with no direct text
    var hasDirectText = false;
    for (var i = 0; i < el.childNodes.length; i++) {
      if (el.childNodes[i].nodeType === 3 && el.childNodes[i].textContent.trim()) {
        hasDirectText = true;
        break;
      }
    }
    if (!hasDirectText) return;

    var fg = parseColor(style.color);
    if (!fg) return;

    var bg = getEffectiveBackground(el);
    var ratio = contrastRatio(fg, bg);
    var fontSize = parseFloat(style.fontSize);
    var isBold = parseInt(style.fontWeight) >= 700 || style.fontWeight === 'bold';
    var isLargeText = fontSize >= 18.66 || (fontSize >= 14 && isBold);
    var required = isLargeText ? 3 : 4.5;

    if (ratio < required) {
      failures.push({
        element: el.tagName.toLowerCase() + (el.className ? '.' + el.className.split(' ')[0] : ''),
        text: el.textContent.trim().substring(0, 50),
        foreground: 'rgb(' + fg.r + ',' + fg.g + ',' + fg.b + ')',
        background: 'rgb(' + bg.r + ',' + bg.g + ',' + bg.b + ')',
        ratio: Math.round(ratio * 100) / 100,
        required: required,
        fontSize: fontSize,
        isLargeText: isLargeText,
        wcagLevel: ratio >= 7 ? 'AAA' : ratio >= 4.5 ? 'AA' : ratio >= 3 ? 'AA-large' : 'FAIL',
        selector: el.id ? '#' + el.id : (el.className ? '.' + el.className.split(' ').join('.') : el.tagName.toLowerCase()),
        rect: (function() { var r = el.getBoundingClientRect(); return { top: r.top, left: r.left, width: r.width, height: r.height }; })()
      });
    }
  });

  return {
    failures: failures,
    totalChecked: textElements.length,
    failCount: failures.length,
    timestamp: new Date().toISOString()
  };
})();
