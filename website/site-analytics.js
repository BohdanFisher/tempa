/* Tempa site analytics — Google Analytics 4 + funnel events.
   Loaded on every page. Everything you may need to change lives in CONFIG. */
(function () {
  "use strict";

  var CONFIG = {
    GA_ID: "G-PEHV0Z956D",

    // Paste the App Store link here the day the app goes live. Every download
    // button on the site then points at it automatically, with an Apple
    // campaign token attached so App Store Connect shows which button/source
    // the install came from. Leave empty until then.
    APP_STORE_URL: "",            // e.g. "https://apps.apple.com/app/id0000000000"

    // Optional "Provider Token" (pt=) from App Store Connect → Campaign Links.
    APPLE_PROVIDER_TOKEN: ""
  };

  /* ---------------------------------------------------------------- gtag */
  var loader = document.createElement("script");
  loader.async = true;
  loader.src = "https://www.googletagmanager.com/gtag/js?id=" + CONFIG.GA_ID;
  document.head.appendChild(loader);

  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = gtag;

  gtag("js", new Date());
  gtag("config", CONFIG.GA_ID);

  /* --------------------------------------------------------------- utils */
  function pageName() {
    var f = location.pathname.split("/").pop() || "index.html";
    return f.replace(/\.html$/, "") || "index";
  }

  function utmSource() {
    try {
      var s = new URLSearchParams(location.search).get("utm_source");
      return s ? s.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 32) : "";
    } catch (e) { return ""; }
  }

  function closestAnchor(node) {
    while (node && node !== document) {
      if (node.tagName === "A") return node;
      node = node.parentNode;
    }
    return null;
  }

  /* ------------------------------------------- App Store link decoration */
  // Turns every [data-download] button into the real store link and tags it
  // with ct=web_<button>_<source> so Apple can attribute the install.
  function decorateDownloadLinks() {
    if (!CONFIG.APP_STORE_URL) return;
    var src = utmSource();
    var links = document.querySelectorAll("[data-download]");
    for (var i = 0; i < links.length; i++) {
      var where = links[i].getAttribute("data-cta") || "site";
      var ct = "web_" + where + (src ? "_" + src : "");
      var url = CONFIG.APP_STORE_URL +
        (CONFIG.APP_STORE_URL.indexOf("?") > -1 ? "&" : "?") +
        "mt=8&ct=" + encodeURIComponent(ct);
      if (CONFIG.APPLE_PROVIDER_TOKEN) {
        url += "&pt=" + encodeURIComponent(CONFIG.APPLE_PROVIDER_TOKEN);
      }
      links[i].href = url;
    }
  }

  /* -------------------------------------------------------------- events */
  function wire() {
    decorateDownloadLinks();

    // 1. download_click — the conversion: someone left for the App Store.
    // 2. support_email_click — someone opened their mail client.
    document.addEventListener("click", function (ev) {
      var a = closestAnchor(ev.target);
      if (!a) return;

      if (a.hasAttribute("data-download")) {
        gtag("event", "download_click", {
          cta_location: a.getAttribute("data-cta") || "unknown",
          page: pageName(),
          link_url: a.href,
          store_link_live: !!CONFIG.APP_STORE_URL
        });
        return;
      }

      var href = a.getAttribute("href") || "";
      if (href.indexOf("mailto:") === 0) {
        gtag("event", "support_email_click", {
          page: pageName(),
          cta_location: a.getAttribute("data-cta") || "body"
        });
      }
    }, true);

    // 3. faq_open — which questions people actually have (home page).
    var faqs = document.querySelectorAll(".faq details");
    for (var i = 0; i < faqs.length; i++) {
      (function (d) {
        d.addEventListener("toggle", function () {
          if (!d.open) return;
          var q = d.querySelector("summary");
          gtag("event", "faq_open", {
            faq_question: q ? q.textContent.trim().slice(0, 100) : ""
          });
        });
      })(faqs[i]);
    }

    // 4. language_select — which languages the legal pages are read in.
    var sw = document.getElementById("lang-switch");
    if (sw) {
      sw.addEventListener("click", function (ev) {
        var a = closestAnchor(ev.target);
        var code = a && a.getAttribute("data-lang");
        if (!code) return;
        gtag("event", "language_select", { language: code, page: pageName() });
      });
      // which language the page opened in on its own (browser / saved choice)
      gtag("event", "legal_page_language", {
        language: document.documentElement.lang || "en",
        page: pageName()
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", wire);
  } else {
    wire();
  }
})();
