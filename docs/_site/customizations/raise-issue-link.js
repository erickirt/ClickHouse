(function () {
  'use strict';

  // Mintlify renders a default "Raise issue" feedback link that opens a blank
  // issue (issues/new?title=Issue on docs&body=Path: <page>). Point it at the
  // repository's Documentation issue form instead, carrying the page path
  // through so the reporter does not have to type it. The path lands in the
  // form's `page` field (matched by its `id` in
  // .github/ISSUE_TEMPLATE/60_documentation-issue.yaml).
  var FORM = 'https://github.com/ClickHouse/ClickHouse/issues/new';
  var TEMPLATE = '60_documentation-issue.yaml';

  function pagePathFrom(href) {
    // Prefer the path Mintlify already encoded in the default link's body
    // ("Path: /foo"); fall back to the current location.
    try {
      var body = new URL(href, window.location.origin).searchParams.get('body') || '';
      var m = body.match(/Path:\s*(\S+)/);
      if (m) return m[1];
    } catch (e) {}
    return window.location.pathname;
  }

  function targetHref(path) {
    return FORM + '?template=' + encodeURIComponent(TEMPLATE) +
      '&page=' + encodeURIComponent(path);
  }

  function isDefaultRaiseIssue(href) {
    // Only touch Mintlify's default "Raise issue" link; leave any other
    // issues/new links (e.g. in page content) alone. Spaces in the title may be
    // encoded as %20 or +, or left literal in the attribute.
    return /\/issues\/new\?/.test(href) &&
      /title=Issue(%20|\+|\s)on(%20|\+|\s)docs/i.test(href);
  }

  var LINK_SELECTOR = 'a[href*="/issues/new"]';

  function rewriteLink(link) {
    if (!link || link.tagName !== 'A') return;
    var href = link.getAttribute('href') || '';
    if (!isDefaultRaiseIssue(href)) return;
    var target = targetHref(pagePathFrom(href));
    if (href !== target) link.setAttribute('href', target);
  }

  function rewriteRoot(root) {
    if (!root || root.nodeType !== 1) return;
    if (root.matches(LINK_SELECTOR)) rewriteLink(root);
    if (!root.querySelector(LINK_SELECTOR)) return;

    // This selector is intentionally scoped to the small feedback toolbar,
    // never the full document or article body.
    var links = root.querySelectorAll(LINK_SELECTOR);
    for (var i = 0; i < links.length; i++) rewriteLink(links[i]);
  }

  var currentContainer = null;
  var currentContentArea = null;
  var currentToolbar = null;
  var containerParentObserver = null;
  var containerObserver = null;
  var contentObserver = null;
  var toolbarObserver = null;
  var bootstrapObserver = null;

  function bindToolbar(toolbar) {
    if (toolbar === currentToolbar) {
      if (toolbar) rewriteRoot(toolbar);
      return;
    }

    if (toolbarObserver) toolbarObserver.disconnect();
    currentToolbar = toolbar;
    if (!toolbar) return;

    rewriteRoot(toolbar);
    toolbarObserver = new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var record = records[i];
        if (record.type === 'attributes') {
          rewriteLink(record.target);
          continue;
        }
        for (var j = 0; j < record.addedNodes.length; j++) {
          rewriteRoot(record.addedNodes[j]);
        }
      }
    });
    toolbarObserver.observe(toolbar, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['href'],
    });
  }

  function bindContentArea(contentArea) {
    if (contentArea === currentContentArea) {
      if (contentArea) bindToolbar(contentArea.querySelector('.feedback-toolbar'));
      return;
    }

    if (contentObserver) contentObserver.disconnect();
    currentContentArea = contentArea;
    bindToolbar(contentArea && contentArea.querySelector('.feedback-toolbar'));
    if (!contentArea) return;

    // The feedback toolbar is a direct child of #content-area. Watching only
    // this level avoids receiving mutations from large article bodies.
    contentObserver = new MutationObserver(function () {
      bindToolbar(contentArea.querySelector('.feedback-toolbar'));
    });
    contentObserver.observe(contentArea, { childList: true });
  }

  function bindContainer() {
    var container = document.getElementById('content-container');
    if (!container) return false;

    if (container !== currentContainer) {
      if (containerParentObserver) containerParentObserver.disconnect();
      if (containerObserver) containerObserver.disconnect();
      currentContainer = container;

      // Catch a shell replacement without observing the document recursively.
      if (container.parentNode) {
        containerParentObserver = new MutationObserver(bindContainer);
        containerParentObserver.observe(container.parentNode, { childList: true });
      }

      containerObserver = new MutationObserver(function () {
        bindContentArea(document.getElementById('content-area'));
      });
      containerObserver.observe(container, { childList: true });
    }

    bindContentArea(document.getElementById('content-area'));
    return true;
  }

  // Mintlify re-renders the feedback toolbar on SPA navigations. Bootstrap
  // recursively only until the stable page shell exists, then switch to direct
  // shell observers and the small feedback subtree.
  function start() {
    if (bindContainer()) return;
    bootstrapObserver = new MutationObserver(function () {
      if (!bindContainer()) return;
      bootstrapObserver.disconnect();
      bootstrapObserver = null;
    });
    bootstrapObserver.observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
