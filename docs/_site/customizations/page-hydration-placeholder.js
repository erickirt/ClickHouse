(function () {
  'use strict';

  var ROOT = document.documentElement;
  var STABLE_CLASS = 'ch-page-hydration-stable';
  var MONITORING_CLASS = 'ch-page-hydration-monitoring';
  var FAILED_OPEN_CLASS = 'ch-page-hydration-failed-open';
  var FUNCTION_PATH_PREFIX = '/reference/functions/';
  var STABLE_SAMPLES_REQUIRED = 4;
  var SAMPLE_INTERVAL_MS = 250;
  var FAIL_OPEN_MS = 45000;

  var userAgent = window.navigator.userAgent;
  var isSafari = /AppleWebKit\//.test(userAgent) &&
    !/(?:Chrome|Chromium|CriOS|Edg|EdgiOS|OPR|OPiOS|FxiOS|Android)\//.test(userAgent);

  var generation = 0;
  var currentPath = '';
  var pendingScrollY = 0;
  var failOpenTimer = null;
  var scrollKeys = {
    ArrowDown: true,
    ArrowUp: true,
    End: true,
    Home: true,
    PageDown: true,
    PageUp: true,
    ' ': true,
  };

  function path() {
    return ROOT.getAttribute('data-current-path') || window.location.pathname;
  }

  function isGatedPath(value) {
    return value.indexOf(FUNCTION_PATH_PREFIX) === 0;
  }

  function announce(status, reason) {
    window.dispatchEvent(new CustomEvent('ch:page-hydration-state', {
      detail: { status: status, reason: reason || '', path: currentPath },
    }));
  }

  function blockScroll(event) {
    if (!ROOT.classList.contains(MONITORING_CLASS)) return;
    event.preventDefault();
  }

  function blockScrollKey(event) {
    if (!ROOT.classList.contains(MONITORING_CLASS) || !scrollKeys[event.key]) return;
    var target = event.target;
    if (target && (target.isContentEditable || /^(?:INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
    event.preventDefault();
  }

  window.addEventListener('wheel', blockScroll, { capture: true, passive: false });
  window.addEventListener('touchmove', blockScroll, { capture: true, passive: false });
  window.addEventListener('keydown', blockScrollKey, { capture: true });

  function removeScrollBlockers() {
    ROOT.classList.remove(MONITORING_CLASS);
  }

  function restoreSafeScrollPosition() {
    if (window.location.hash) {
      var id;
      try { id = decodeURIComponent(window.location.hash.slice(1)); }
      catch (error) { id = window.location.hash.slice(1); }
      var target = document.getElementById(id);
      if (target) {
        target.scrollIntoView();
        return;
      }
    }
    if (pendingScrollY > 0) window.scrollTo(0, pendingScrollY);
  }

  function reveal(reason, failedOpen) {
    if (failOpenTimer) {
      clearTimeout(failOpenTimer);
      failOpenTimer = null;
    }
    if (failedOpen) ROOT.classList.add(FAILED_OPEN_CLASS);
    else ROOT.classList.remove(FAILED_OPEN_CLASS);
    ROOT.classList.add(STABLE_CLASS);
    ROOT.setAttribute('data-page-hydration-state', failedOpen ? 'failed-open' : 'stable');
    removeScrollBlockers();
    window.requestAnimationFrame(restoreSafeScrollPosition);
    announce('stable', reason);
  }

  function begin() {
    var nextPath = path();
    currentPath = nextPath;
    generation += 1;
    var run = generation;

    if (!isSafari || !isGatedPath(nextPath)) {
      ROOT.classList.add(STABLE_CLASS);
      removeScrollBlockers();
      return;
    }

    pendingScrollY = window.scrollY;
    ROOT.classList.remove(STABLE_CLASS, FAILED_OPEN_CLASS);
    ROOT.classList.add(MONITORING_CLASS);
    ROOT.setAttribute('data-page-hydration-state', 'loading');
    // The fixed placeholder may have appeared before this controller executed.
    // Reset any background scrolling that occurred behind it; restore browser
    // history/hash positions only after the document geometry is stable.
    window.scrollTo(0, 0);
    announce('loading');

    var fontsReady = !document.fonts;
    if (document.fonts) {
      document.fonts.ready.then(function () { fontsReady = true; });
    }

    var lastSignature = '';
    var stableSamples = 0;

    function sample() {
      if (run !== generation) return;
      if (path() !== currentPath) {
        begin();
        return;
      }

      var content = document.getElementById('content-area');
      var footer = document.getElementById('ch-custom-footer');
      var rootScroller = document.scrollingElement || ROOT;
      var ready = document.readyState === 'complete' && fontsReady && content && footer;

      if (ready) {
        var contentHeight = Math.round(content.getBoundingClientRect().height);
        var signature = [
          contentHeight,
          rootScroller.scrollHeight,
          content.childElementCount,
        ].join(':');

        if (signature === lastSignature && contentHeight > 0) stableSamples += 1;
        else stableSamples = 0;
        lastSignature = signature;

        if (stableSamples >= STABLE_SAMPLES_REQUIRED) {
          reveal('geometry-stable', false);
          return;
        }
      } else {
        stableSamples = 0;
        lastSignature = '';
      }

      window.setTimeout(sample, SAMPLE_INTERVAL_MS);
    }

    if (failOpenTimer) clearTimeout(failOpenTimer);
    failOpenTimer = window.setTimeout(function () {
      if (run === generation) reveal('safety-limit', true);
    }, FAIL_OPEN_MS);

    sample();
  }

  // Mintlify updates this server-rendered attribute on client-side routes.
  new MutationObserver(function (records) {
    for (var i = 0; i < records.length; i += 1) {
      if (records[i].attributeName === 'data-current-path' && path() !== currentPath) {
        begin();
        return;
      }
    }
  }).observe(ROOT, { attributes: true, attributeFilter: ['data-current-path'] });

  window.addEventListener('popstate', function () {
    window.setTimeout(begin, 0);
  });

  begin();
})();
