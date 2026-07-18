(function () {
  'use strict';

  // ── Desktop tab navigation ────────────────────────────────────────────────
  var TAB_URLS = {
    'Home':         '/',
    'Database':     '/get-started/about/intro',
    'Solutions':    '/products/cloud/getting-started/cloud-get-started',
    'Integrations': '/integrations/home',
  };

  // Locales with their own page tree; each has a localized homepage at
  // /<locale> and mirrors the English paths beneath it.
  var LOCALES = ['ar', 'es', 'fr', 'ja', 'ko', 'pt-BR', 'ru', 'zh'];

  // '' at root (.app, mint dev); '/docs' on the subpath deploy
  var BASE = /^\/docs(\/|$)/.test(window.location.pathname) ? '/docs' : '';
  function stripBase(p) { return (BASE && p.indexOf(BASE) === 0) ? (p.slice(BASE.length) || '/') : p; }

  function currentLocale() {
    var seg = stripBase(window.location.pathname).split('/')[1] || '';
    return LOCALES.indexOf(seg) !== -1 ? seg : '';
  }

  // Keep navigation within the active locale and base path.
  function localizeUrl(url) {
    var locale = currentLocale();
    var localized = locale ? '/' + locale + (url === '/' ? '' : url) : url;
    return BASE + localized;
  }

  var TAB_SELECTOR = 'button.nav-tabs-item, a.nav-tabs-item';
  var MOBILE_TAB_SELECTOR = 'a.mobile-nav-tabs-item';

  function patchTabElement(el) {
    if (el.dataset.tabNavAttached) return;

    var labelDiv = el.querySelector('div');
    if (!labelDiv) return;

    var text = (labelDiv.textContent || '').trim();
    var url = TAB_URLS[text];
    if (!url) return;

    el.dataset.tabNavAttached = '1';

    if (el.tagName === 'A') {
      el.setAttribute('href', localizeUrl(url));
      return;
    }

    labelDiv.style.cursor = 'pointer';
    labelDiv.addEventListener('click', function (e) {
      e.stopPropagation();
      window.location.href = localizeUrl(url);
    });
  }

  function patchTabRoot(root) {
    // Only run on desktop.
    if (window.innerWidth < 1024 || !root || !root.querySelector) return;
    if (root.nodeType === 1 && root.matches(TAB_SELECTOR)) patchTabElement(root);
    if (!root.querySelector(TAB_SELECTOR)) return;

    var tabs = root.querySelectorAll(TAB_SELECTOR);
    for (var i = 0; i < tabs.length; i++) patchTabElement(tabs[i]);
  }

  function patchTabButtons() {
    patchTabRoot(document);
  }

  // ── Mobile section header styling ─────────────────────────────────────────
  var SECTION_HEADERS = ['ClickHouse', 'Open source'];

  function styleDropdownHeader(a) {
    if (a.dataset.headerStyled) return;
    var text = (a.textContent || '').trim();
    if (SECTION_HEADERS.indexOf(text) === -1) return;

    a.dataset.headerStyled = '1';
    a.style.fontWeight = '700';
    a.style.fontSize = '0.75rem';
    a.style.letterSpacing = '0.05em';
    a.style.textTransform = 'uppercase';
    a.style.opacity = '0.5';
    a.style.pointerEvents = 'none';
    a.style.cursor = 'default';
    a.style.borderBottom = '1px solid rgba(255,255,255,0.08)';
    a.style.paddingBottom = '8px';
    a.style.marginBottom = '2px';

    a.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
    });
  }

  function styleDropdownRoot(root) {
    if (!root || !root.querySelector) return;
    if (root.nodeType === 1 && root.matches(MOBILE_TAB_SELECTOR)) styleDropdownHeader(root);
    if (!root.querySelector(MOBILE_TAB_SELECTOR)) return;

    var tabs = root.querySelectorAll(MOBILE_TAB_SELECTOR);
    for (var i = 0; i < tabs.length; i++) styleDropdownHeader(tabs[i]);
  }

  function styleDropdownHeaders() {
    styleDropdownRoot(document);
  }

  // ── Logo theme sync ──────────────────────────────────────────────────────
  function updateLogoTheme() {
    var light = document.getElementById('ch-hp-logo-light');
    var dark = document.getElementById('ch-hp-logo-dark');
    if (!light || !dark) return;
    var isDark = document.documentElement.classList.contains('dark');
    light.style.display = isDark ? 'none' : 'block';
    dark.style.display = isDark ? 'block' : 'none';
  }

  // ── Homepage sidebar hiding ───────────────────────────────────────────────
  // Each locale has its own homepage at /<locale> (e.g. /es, /ja); treat those
  // the same as the English homepage at /.
  function isHomePath() {
    var path = stripBase(window.location.pathname).replace(/\/+$/, '') || '/';
    return path === '/' || LOCALES.indexOf(path.slice(1)) !== -1;
  }

  function applyHomepageClass() {
    if (isHomePath()) {
      document.documentElement.classList.add('ch-homepage');
    } else {
      document.documentElement.classList.remove('ch-homepage');
    }
  }

  // ── Homepage: inject logo + theme toggle into navbar ──────────────────────
  var LOGO_ID = 'ch-homepage-logo';
  var TOGGLE_ID = 'ch-homepage-toggle';

  function findSidebarThemeToggle() {
    // Current Mintlify builds render a segmented control: a
    //   <div role="group" aria-label="Theme preference">
    // wrapping three buttons (system / light / dark). We relocate the whole
    // group so all three options move together.
    var group = document.querySelector('#sidebar [role="group"][aria-label="Theme preference"]');
    if (group) return group;
    // Older builds rendered a single <button aria-label="Toggle dark mode">.
    var btn = document.querySelector('#sidebar button[aria-label="Toggle dark mode"]');
    if (btn) return btn;
    // Localized UIs translate the aria-label (e.g. "다크 모드 전환"), so fall
    // back to the control's shape: the only sidebar pill (rounded-full) holding
    // the theme icons — matches both the segmented group and the legacy button.
    var candidates = document.querySelectorAll('#sidebar [role="group"], #sidebar button');
    for (var i = 0; i < candidates.length; i++) {
      if (/rounded-full/.test(candidates[i].className)
          && candidates[i].querySelectorAll('svg').length >= 2) {
        return candidates[i];
      }
    }
    return null;
  }

  function setupHomepageNavbar() {
    var isHome = isHomePath();
    var navbar = document.getElementById('navbar-transition-maple');
    if (!navbar) return;

    if (!isHome) {
      // Restore theme toggle to sidebar before removing wrapper
      var toggleWrapper = document.getElementById(TOGGLE_ID);
      if (toggleWrapper) {
        // Move the whole control back — it may be a segmented group (a div with
        // several buttons), not a single button, so restore firstElementChild.
        var control = toggleWrapper.firstElementChild;
        var sidebar = document.getElementById('sidebar');
        if (control && sidebar) sidebar.appendChild(control);
        toggleWrapper.parentNode.removeChild(toggleWrapper);
      }
      var logo = document.getElementById(LOGO_ID);
      if (logo) logo.parentNode.removeChild(logo);
      return;
    }

    // Inject logo at left of navbar; link to the active locale's homepage
    var existingLogo = document.getElementById(LOGO_ID);
    if (existingLogo) {
      existingLogo.setAttribute('href', localizeUrl('/'));
    } else {
      var logoLink = document.createElement('a');
      logoLink.id = LOGO_ID;
      logoLink.href = localizeUrl('/');
      logoLink.innerHTML = '<img src="' + BASE + '/_site/logo/light.svg" id="ch-hp-logo-light" alt="ClickHouse Docs">'
        + '<img src="' + BASE + '/_site/logo/dark.svg" id="ch-hp-logo-dark" alt="ClickHouse Docs">';
      navbar.insertBefore(logoLink, navbar.firstChild);
      updateLogoTheme();
    }

    // Move theme toggle from sidebar to navbar — insert after logo, before tabs.
    // margin-right: auto pushes all tabs + right-side controls to the right.
    if (!document.getElementById(TOGGLE_ID)) {
      var sidebarToggle = findSidebarThemeToggle();
      if (sidebarToggle) {
        var wrapper = document.createElement('div');
        wrapper.id = TOGGLE_ID;
        wrapper.style.cssText = 'display:flex;align-items:center;flex-shrink:0;margin-left:0.75rem;margin-right:auto;';
        sidebarToggle.parentNode.removeChild(sidebarToggle);
        wrapper.appendChild(sidebarToggle);
        // Insert as second child (right after the logo)
        var logoEl = document.getElementById(LOGO_ID);
        if (logoEl && logoEl.nextSibling) {
          navbar.insertBefore(wrapper, logoEl.nextSibling);
        } else {
          navbar.appendChild(wrapper);
        }
      }
    }
  }

  // ── Navbar ready ──────────────────────────────────────────────────────────
  // Reveal the navbar once both injections are complete: logo (homepage only)
  // and CTA (all pages). Called via requestAnimationFrame so it runs after the
  // current synchronous task — giving navbar-cta.js time to inject the CTA
  // before we check. The targeted navbar observer retries when the CTA mounts.
  function markNavbarReady() {
    var navbar = document.getElementById('navbar-transition-maple');
    if (!navbar) return;
    if (!document.getElementById('ch-navbar-cta')) return;
    if (isHomePath() && !document.getElementById(LOGO_ID)) return;
    navbar.classList.add('ch-navbar-ready');
    // Latch the reveal on <html> (which survives SPA navigations) so the
    // first-load hide guard in CSS never re-applies on subsequent in-app
    // navigations — preventing a fade on every page change.
    document.documentElement.classList.add('ch-navbar-revealed');
  }

  // ── Targeted DOM observation ───────────────────────────────────────────────
  var pendingRoots = [];
  var rootsRafId = null;
  var shellWorkPending = false;
  var currentNavbar = null;
  var currentSidebar = null;
  var navbarObserver = null;
  var navbarParentObserver = null;
  var sidebarObserver = null;
  var sidebarParentObserver = null;
  var bodyObserver = null;
  var bootstrapObserver = null;

  function queueRoot(node) {
    if (!node || node.nodeType !== 1) return;
    for (var i = pendingRoots.length - 1; i >= 0; i--) {
      if (pendingRoots[i].contains(node)) return;
      if (node.contains(pendingRoots[i])) pendingRoots.splice(i, 1);
    }
    pendingRoots.push(node);
  }

  function queueRecords(records, includeShellWork) {
    if (includeShellWork) shellWorkPending = true;
    for (var i = 0; i < records.length; i++) {
      for (var j = 0; j < records[i].addedNodes.length; j++) {
        queueRoot(records[i].addedNodes[j]);
      }
    }
    scheduleRootFlush();
  }

  function scheduleRootFlush() {
    if (rootsRafId) return;
    rootsRafId = requestAnimationFrame(function () {
      rootsRafId = null;
      var roots = pendingRoots;
      pendingRoots = [];
      for (var i = 0; i < roots.length; i++) {
        patchTabRoot(roots[i]);
        styleDropdownRoot(roots[i]);
      }

      if (shellWorkPending) {
        shellWorkPending = false;
        bindObservedShell();
        setupHomepageNavbar();
        updateLogoTheme();
        markNavbarReady();
      }
    });
  }

  function observeTarget(target, oldObserver, options) {
    if (oldObserver) oldObserver.disconnect();
    if (!target) return null;
    var observer = new MutationObserver(function (records) {
      queueRecords(records, true);
    });
    observer.observe(target, options);
    return observer;
  }

  function bindObservedShell() {
    var navbar = document.getElementById('navbar-transition-maple');
    if (navbar !== currentNavbar) {
      navbarObserver = observeTarget(navbar, navbarObserver, { childList: true, subtree: true });
      navbarParentObserver = observeTarget(
        navbar && navbar.parentNode,
        navbarParentObserver,
        { childList: true }
      );
      currentNavbar = navbar;
    }

    var sidebar = document.getElementById('sidebar');
    if (sidebar !== currentSidebar) {
      sidebarObserver = observeTarget(sidebar, sidebarObserver, { childList: true, subtree: true });
      sidebarParentObserver = observeTarget(
        sidebar && sidebar.parentNode,
        sidebarParentObserver,
        { childList: true }
      );
      currentSidebar = sidebar;
    }

    // The recursive bootstrap observer is only needed while React is mounting
    // the stable navbar/sidebar shell.
    if (navbar && sidebar && bootstrapObserver) {
      bootstrapObserver.disconnect();
      bootstrapObserver = null;
    } else if (bodyObserver && (!navbar || !sidebar) && !bootstrapObserver) {
      bootstrapObserver = new MutationObserver(function (records) {
        queueRecords(records, true);
      });
      bootstrapObserver.observe(document.documentElement, { childList: true, subtree: true });
    }
  }

  function startTargetedObservers() {
    bindObservedShell();

    // Portals (including the mobile nav dropdown) are mounted as direct body
    // children. Process their added subtree once instead of watching the full
    // document recursively for the lifetime of the page.
    bodyObserver = new MutationObserver(function (records) {
      queueRecords(records, true);
    });
    bodyObserver.observe(document.body, { childList: true });

    if (!currentNavbar || !currentSidebar) {
      bootstrapObserver = new MutationObserver(function (records) {
        queueRecords(records, true);
      });
      bootstrapObserver.observe(document.documentElement, { childList: true, subtree: true });
    }

    // Theme changes only need a class check; article mutations are irrelevant.
    new MutationObserver(updateLogoTheme).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class'],
    });
  }

  // ── Route changes ──────────────────────────────────────────────────────────
  var lastPath = window.location.pathname;

  function handlePathChange() {
    if (window.location.pathname === lastPath) return;
    lastPath = window.location.pathname;
    applyHomepageClass();
    setupHomepageNavbar();
    patchTabButtons();
    styleDropdownHeaders();
    markNavbarReady();
    bindObservedShell();
  }

  function wrapHistoryMethod(name) {
    var original = window.history[name];
    window.history[name] = function () {
      var result = original.apply(this, arguments);
      handlePathChange();
      return result;
    };
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  function init() {
    applyHomepageClass();
    setupHomepageNavbar();
    patchTabButtons();
    styleDropdownHeaders();
    markNavbarReady();
    startTargetedObservers();

    window.addEventListener('resize', patchTabButtons);
    wrapHistoryMethod('pushState');
    wrapHistoryMethod('replaceState');
    window.addEventListener('popstate', handlePathChange);
    if (window.navigation && typeof window.navigation.addEventListener === 'function') {
      window.navigation.addEventListener('currententrychange', handlePathChange);
    }

    // Failsafe: never leave the navbar hidden. If an injection never completes
    // (so markNavbarReady never latches the reveal), force-reveal after a
    // generous delay — but only once the navbar actually exists, so a late
    // mount still gets the initial opacity hide instead of flashing in.
    setTimeout(function retryNavbarReveal() {
      if (!document.getElementById('navbar-transition-maple')) {
        setTimeout(retryNavbarReveal, 100);
        return;
      }
      document.documentElement.classList.add('ch-navbar-revealed');
    }, 2000);
  }

  // Apply the homepage class immediately at script evaluation time — before the
  // navbar is inserted by React hydration — so justify-content:flex-start and
  // other ch-homepage navbar rules apply from the very first navbar paint.
  applyHomepageClass();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
