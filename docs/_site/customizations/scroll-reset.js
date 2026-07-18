(function () {
  'use strict';

  // With an announcement banner configured, Next.js skips its scroll-to-top
  // on client-side navigation: the banner is position:fixed at the top of the
  // re-rendered segment, so the router considers the new page "already in
  // viewport" and leaves the scroll position where it was. (Banner-less
  // Mintlify sites scroll to top as expected; dismissing the banner makes the
  // bug disappear.) Restore the expected behavior by scrolling to the top
  // whenever a forward navigation changes the path.
  //
  // Route notifications come from History, popstate, the Navigation API, and
  // narrow page-shell observers. The DOM fallback covers routers that captured
  // native History methods before this customization loaded without polling on
  // every animation frame.
  //
  // Back/forward (popstate) is deliberately left alone so the browser and
  // router can restore the previous scroll position. Cross-page hash links
  // (/page#anchor) scroll to the anchor once the new page has rendered it,
  // since the banner bug breaks that scroll too.
  var lastPath = window.location.pathname;
  var traversed = false;

  window.addEventListener('popstate', function () {
    if (window.location.pathname !== lastPath) {
      traversed = true;
    }
    handlePathChange();
  });

  // The new page renders some frames after the path changes, so poll for the
  // anchor target before scrolling to it; if it never appears (bad anchor),
  // fall back to the top rather than keeping the old page's position.
  function scrollToAnchor(hash, framesLeft) {
    var id;
    try { id = decodeURIComponent(hash.slice(1)); } catch (e) { id = hash.slice(1); }
    var el = document.getElementById(id);
    if (el) {
      el.scrollIntoView();
      return;
    }
    if (framesLeft > 0 && window.location.hash === hash) {
      window.requestAnimationFrame(function () { scrollToAnchor(hash, framesLeft - 1); });
    } else {
      window.scrollTo(0, 0);
    }
  }

  function handlePathChange() {
    var path = window.location.pathname;
    if (path === lastPath) return;
    lastPath = path;
    if (traversed) {
      traversed = false;
    } else if (window.location.hash) {
      scrollToAnchor(window.location.hash, 180);
    } else {
      window.scrollTo(0, 0);
    }
  }

  function wrapHistoryMethod(name) {
    var original = window.history[name];
    window.history[name] = function () {
      var result = original.apply(this, arguments);
      handlePathChange();
      return result;
    };
  }

  wrapHistoryMethod('pushState');
  wrapHistoryMethod('replaceState');

  // currententrychange also fires when an app retained a native History method.
  // Defer its check so popstate can mark traversals before we decide whether to
  // preserve the browser-restored position.
  if (window.navigation && typeof window.navigation.addEventListener === 'function') {
    window.navigation.addEventListener('navigate', function (event) {
      if (event.navigationType === 'traverse') traversed = true;
    });
    window.navigation.addEventListener('currententrychange', function () {
      setTimeout(handlePathChange, 0);
    });
  }

  // A user-initiated SPA navigation always starts with an internal link click.
  // One post-click frame catches routers that bypass both wrapped History and
  // the Navigation API; unlike the old loop, it runs only during navigation.
  document.addEventListener('click', function (event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey ||
        event.ctrlKey || event.shiftKey || event.altKey) return;
    var link = event.target && event.target.closest && event.target.closest('a[href]');
    if (!link) return;
    var url;
    try { url = new URL(link.href, window.location.href); } catch (e) { return; }
    if (url.origin !== window.location.origin || url.pathname === lastPath) return;
    setTimeout(handlePathChange, 0);
    window.requestAnimationFrame(handlePathChange);
  }, true);

  // Next.js replaces children of these stable shell nodes during an SPA route.
  // Observe only direct children so article highlighting and third-party widget
  // mutations do not wake this script.
  var currentContainer = null;
  var currentContentArea = null;
  var containerParentObserver = null;
  var containerObserver = null;
  var contentObserver = null;
  var bootstrapObserver = null;

  function onShellMutation() {
    bindShellObservers();
    handlePathChange();
  }

  function bindShellObservers() {
    var container = document.getElementById('content-container');
    if (container !== currentContainer) {
      if (containerParentObserver) containerParentObserver.disconnect();
      if (containerObserver) containerObserver.disconnect();
      currentContainer = container;

      if (container && container.parentNode) {
        containerParentObserver = new MutationObserver(onShellMutation);
        containerParentObserver.observe(container.parentNode, { childList: true });
      }
      if (container) {
        containerObserver = new MutationObserver(onShellMutation);
        containerObserver.observe(container, { childList: true });
      }
    }

    var contentArea = document.getElementById('content-area');
    if (contentArea !== currentContentArea) {
      if (contentObserver) contentObserver.disconnect();
      currentContentArea = contentArea;
      if (contentArea) {
        contentObserver = new MutationObserver(onShellMutation);
        contentObserver.observe(contentArea, { childList: true });
      }
    }

    if (container && contentArea && bootstrapObserver) {
      bootstrapObserver.disconnect();
      bootstrapObserver = null;
    }

    return Boolean(container && contentArea);
  }

  if (!bindShellObservers()) {
    bootstrapObserver = new MutationObserver(onShellMutation);
    bootstrapObserver.observe(document.documentElement, { childList: true, subtree: true });
    // Pages without the normal docs shell still use the History/click sources;
    // do not leave a recursive bootstrap observer running indefinitely.
    setTimeout(function () {
      if (!bootstrapObserver) return;
      bootstrapObserver.disconnect();
      bootstrapObserver = null;
    }, 10000);
  }
})();
