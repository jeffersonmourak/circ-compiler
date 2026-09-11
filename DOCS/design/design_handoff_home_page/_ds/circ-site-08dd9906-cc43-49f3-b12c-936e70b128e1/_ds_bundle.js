/* @ds-bundle: {"namespace":"CircDS","components":[{"name":"AlphaWarning","sourcePath":"components/content/AlphaWarning/AlphaWarning.jsx"},{"name":"CodePreview","sourcePath":"components/code/CodePreview/CodePreview.jsx"},{"name":"CommandSnippet","sourcePath":"components/code/CommandSnippet/CommandSnippet.jsx"},{"name":"DocsPage","sourcePath":"components/layout/DocsPage/DocsPage.jsx"},{"name":"DownloadTable","sourcePath":"components/download/DownloadTable/DownloadTable.jsx"},{"name":"ExampleCard","sourcePath":"components/content/ExampleCard/ExampleCard.jsx"},{"name":"Footer","sourcePath":"components/navigation/Footer/Footer.jsx"},{"name":"InstallLine","sourcePath":"components/download/InstallLine/InstallLine.jsx"},{"name":"Lineage","sourcePath":"components/content/Lineage/Lineage.jsx"},{"name":"LiveCanvas","sourcePath":"components/code/LiveCanvas/LiveCanvas.jsx"},{"name":"Nav","sourcePath":"components/navigation/Nav/Nav.jsx"},{"name":"Prose","sourcePath":"components/layout/Prose/Prose.jsx"},{"name":"SiteShell","sourcePath":"components/layout/SiteShell/SiteShell.jsx"},{"name":"StatusNote","sourcePath":"components/content/StatusNote/StatusNote.jsx"},{"name":"Tagline","sourcePath":"components/content/Tagline/Tagline.jsx"},{"name":"ThemeToggle","sourcePath":"components/navigation/ThemeToggle/ThemeToggle.jsx"},{"name":"TourStep","sourcePath":"components/content/TourStep/TourStep.jsx"}],"sourceHashes":{"components/content/AlphaWarning/AlphaWarning.jsx":"8bbdb6de02f9","components/content/AlphaWarning/AlphaWarning.d.ts":"ce0e5ee658f1","components/content/AlphaWarning/AlphaWarning.prompt.md":"1c0913746ad1","components/code/CodePreview/CodePreview.jsx":"7e667a01c5fc","components/code/CodePreview/CodePreview.d.ts":"05ccfabc4a72","components/code/CodePreview/CodePreview.prompt.md":"6c294770a651","components/code/CommandSnippet/CommandSnippet.jsx":"9b8f3d07c252","components/code/CommandSnippet/CommandSnippet.d.ts":"b443823c8c17","components/code/CommandSnippet/CommandSnippet.prompt.md":"1f2da4818ffe","components/layout/DocsPage/DocsPage.jsx":"f41030bd5f22","components/layout/DocsPage/DocsPage.d.ts":"ff429d8740e4","components/layout/DocsPage/DocsPage.prompt.md":"e892f4d011c6","components/download/DownloadTable/DownloadTable.jsx":"915ae4c0fd96","components/download/DownloadTable/DownloadTable.d.ts":"a42ee65c6e52","components/download/DownloadTable/DownloadTable.prompt.md":"0aaa509fb009","components/content/ExampleCard/ExampleCard.jsx":"aca1b5b3fcc6","components/content/ExampleCard/ExampleCard.d.ts":"4d750d8a2fd0","components/content/ExampleCard/ExampleCard.prompt.md":"e2fb98b59a45","components/navigation/Footer/Footer.jsx":"017ca1210355","components/navigation/Footer/Footer.d.ts":"17057a064311","components/navigation/Footer/Footer.prompt.md":"c531dc1fabc2","components/download/InstallLine/InstallLine.jsx":"a4263a023014","components/download/InstallLine/InstallLine.d.ts":"3407ec39e618","components/download/InstallLine/InstallLine.prompt.md":"3ab6f2fa7bf3","components/content/Lineage/Lineage.jsx":"52592477ce85","components/content/Lineage/Lineage.d.ts":"7ddaef8ba708","components/content/Lineage/Lineage.prompt.md":"ed82616f0de4","components/code/LiveCanvas/LiveCanvas.jsx":"079aeee10cac","components/code/LiveCanvas/LiveCanvas.d.ts":"a34eb34edd80","components/code/LiveCanvas/LiveCanvas.prompt.md":"eb80dd3e14fa","components/navigation/Nav/Nav.jsx":"0613e15ae0b0","components/navigation/Nav/Nav.d.ts":"e6c69db4befa","components/navigation/Nav/Nav.prompt.md":"a34c98436343","components/layout/Prose/Prose.jsx":"02c3a1cfbc43","components/layout/Prose/Prose.d.ts":"5c82f5ff3dc6","components/layout/Prose/Prose.prompt.md":"162c954af3f1","components/layout/SiteShell/SiteShell.jsx":"e4a82d9b380f","components/layout/SiteShell/SiteShell.d.ts":"315dc0123a5e","components/layout/SiteShell/SiteShell.prompt.md":"e4ec8b77542b","components/content/StatusNote/StatusNote.jsx":"c743bfc79ca9","components/content/StatusNote/StatusNote.d.ts":"bcc70f26553d","components/content/StatusNote/StatusNote.prompt.md":"317f09d5f957","components/content/Tagline/Tagline.jsx":"183274186597","components/content/Tagline/Tagline.d.ts":"9aefc46b68c2","components/content/Tagline/Tagline.prompt.md":"811482e80d93","components/navigation/ThemeToggle/ThemeToggle.jsx":"e11e7b6e8eb6","components/navigation/ThemeToggle/ThemeToggle.d.ts":"4c12e52e4410","components/navigation/ThemeToggle/ThemeToggle.prompt.md":"cd5692ac03a3","components/content/TourStep/TourStep.jsx":"c26950e2db93","components/content/TourStep/TourStep.d.ts":"283b916cf2b2","components/content/TourStep/TourStep.prompt.md":"aa01e1cddf96"},"inlinedExternals":[],"builtBy":"cc-design-sync"} */
"use strict";
var CircDS = (() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __esm = (fn, res, err) => function __init() {
    if (err) throw err[0];
    try {
      return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
    } catch (e) {
      throw err = [e], e;
    }
  };
  var __commonJS = (cb, mod) => function __require() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // <define:import.meta.env>
  var init_define_import_meta_env = __esm({
    "<define:import.meta.env>"() {
    }
  });

  // shim:react-shim
  var require_react_shim = __commonJS({
    "shim:react-shim"(exports, module) {
      init_define_import_meta_env();
      var R = window.React;
      function np(p, k) {
        var o = {};
        for (var x in p) if (x !== "children") o[x] = p[x];
        if (k !== void 0) o.key = k;
        return o;
      }
      function jsx(t, p, k) {
        var c = p && p.children;
        return c === void 0 ? R.createElement(t, np(p, k)) : R.createElement(t, np(p, k), c);
      }
      function jsxs(t, p, k) {
        return R.createElement.apply(R, [t, np(p, k)].concat(p.children));
      }
      module.exports = R;
      module.exports.jsx = jsx;
      module.exports.jsxs = jsxs;
      module.exports.jsxDEV = function(t, p, k, s) {
        return (s ? jsxs : jsx)(t, p, k);
      };
      module.exports.Fragment = R.Fragment;
    }
  });

  // dist/index.js
  var index_exports = {};
  __export(index_exports, {
    AlphaWarning: () => AlphaWarning,
    CodePreview: () => CodePreview,
    CommandSnippet: () => CommandSnippet,
    DocsPage: () => DocsPage,
    DownloadTable: () => DownloadTable,
    ExampleCard: () => ExampleCard,
    Footer: () => Footer,
    InstallLine: () => InstallLine,
    Lineage: () => Lineage,
    LiveCanvas: () => LiveCanvas,
    Nav: () => Nav,
    Prose: () => Prose,
    SiteShell: () => SiteShell,
    StatusNote: () => StatusNote,
    Tagline: () => Tagline,
    ThemeToggle: () => ThemeToggle,
    TourStep: () => TourStep
  });
  init_define_import_meta_env();

  // dist/components/SiteShell.js
  init_define_import_meta_env();
  var import_jsx_runtime4 = __toESM(require_react_shim(), 1);

  // dist/components/Nav.js
  init_define_import_meta_env();
  var import_jsx_runtime2 = __toESM(require_react_shim(), 1);
  var import_react = __toESM(require_react_shim(), 1);

  // dist/components/ThemeToggle.js
  init_define_import_meta_env();
  var import_jsx_runtime = __toESM(require_react_shim(), 1);
  function ThemeToggle({ label = "Toggle dark mode", icon = "\u25D0", className, style }) {
    const toggle = () => {
      const root = document.documentElement;
      const next = root.dataset.theme === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      try {
        localStorage.setItem("theme", next);
      } catch {
      }
    };
    return (0, import_jsx_runtime.jsx)("button", { type: "button", className: className ? `theme-toggle ${className}` : "theme-toggle", "aria-label": label, style, onClick: toggle, children: (0, import_jsx_runtime.jsx)("span", { className: "theme-icon", "aria-hidden": "true", children: icon }) });
  }

  // dist/components/Nav.js
  var DEFAULT_LINKS = [
    { href: "/tour", label: "Tour" },
    { href: "/reference", label: "Reference" },
    { href: "/examples", label: "Examples" },
    { href: "/download", label: "Download" }
  ];
  function Nav({ brand = "circ", brandHref = "/", links = DEFAULT_LINKS, githubHref = "https://github.com/jeffersonmourak/circ-compiler", githubPublic = true }) {
    const [open, setOpen] = (0, import_react.useState)(false);
    return (0, import_jsx_runtime2.jsxs)("header", { className: "site-nav", children: [(0, import_jsx_runtime2.jsx)("a", { href: brandHref, className: "brand", children: (0, import_jsx_runtime2.jsx)("span", { className: "brand-mark", children: brand }) }), (0, import_jsx_runtime2.jsxs)("button", { className: "nav-toggle", type: "button", "aria-expanded": open, "aria-controls": "primary-nav", "aria-label": "Toggle menu", onClick: () => setOpen((v) => !v), children: [(0, import_jsx_runtime2.jsx)("span", { className: "nav-toggle-bar" }), (0, import_jsx_runtime2.jsx)("span", { className: "nav-toggle-bar" }), (0, import_jsx_runtime2.jsx)("span", { className: "nav-toggle-bar" })] }), (0, import_jsx_runtime2.jsx)("nav", { id: "primary-nav", "aria-label": "Primary", ...open ? { "data-open": "" } : {}, children: (0, import_jsx_runtime2.jsxs)("ul", { children: [links.map((l) => (0, import_jsx_runtime2.jsx)("li", { children: (0, import_jsx_runtime2.jsx)("a", { href: l.href, onClick: () => setOpen(false), children: l.label }) }, l.href)), (0, import_jsx_runtime2.jsx)("li", { children: githubPublic ? (0, import_jsx_runtime2.jsx)("a", { href: githubHref, rel: "noreferrer noopener", children: "GitHub" }) : (0, import_jsx_runtime2.jsxs)("span", { className: "link-soon", title: "Repo goes public once circ-compiler is ready to share", children: ["GitHub ", (0, import_jsx_runtime2.jsx)("small", { children: "(soon)" })] }) })] }) }), (0, import_jsx_runtime2.jsx)(ThemeToggle, {})] });
  }

  // dist/components/Footer.js
  init_define_import_meta_env();
  var import_jsx_runtime3 = __toESM(require_react_shim(), 1);
  var DEFAULT_LINKS2 = [
    { href: "/tour", label: "Tour" },
    { href: "/reference", label: "Reference" },
    { href: "/examples", label: "Examples" }
  ];
  var DEFAULT_COLOPHON = (0, import_jsx_runtime3.jsxs)(import_jsx_runtime3.Fragment, { children: ["Typeset in", " ", (0, import_jsx_runtime3.jsx)("a", { href: "https://www.collletttivo.it/typefaces/ronzino", rel: "noreferrer noopener", children: "Ronzino" }), " ", "&", " ", (0, import_jsx_runtime3.jsx)("a", { href: "https://www.collletttivo.it/typefaces/necto-mono", rel: "noreferrer noopener", children: "Necto\xA0Mono" }), " ", "\u2014 thanks to", " ", (0, import_jsx_runtime3.jsx)("a", { href: "https://www.collletttivo.it", rel: "noreferrer noopener", children: "Collletttivo" }), " ", "for the fonts."] });
  var DEFAULT_SIGNATURE = (0, import_jsx_runtime3.jsxs)(import_jsx_runtime3.Fragment, { children: ["Made with", " ", (0, import_jsx_runtime3.jsx)("span", { className: "heart", "aria-hidden": "true", children: "\u2665\uFE0E" }), (0, import_jsx_runtime3.jsx)("span", { className: "visually-hidden", children: "love" }), " by", " ", (0, import_jsx_runtime3.jsx)("a", { href: "https://github.com/jeffersonmourak", rel: "noreferrer noopener", children: "@jeffersonmourak" })] });
  function Footer({ links = DEFAULT_LINKS2, githubHref = "https://github.com/jeffersonmourak/circ-compiler", githubPublic = true, license = "circ is open source under the GNU GPL v3.", colophon = DEFAULT_COLOPHON, signature = DEFAULT_SIGNATURE }) {
    return (0, import_jsx_runtime3.jsxs)("footer", { className: "site-footer", children: [(0, import_jsx_runtime3.jsxs)("div", { className: "site-footer-row", children: [(0, import_jsx_runtime3.jsxs)("div", { className: "links", children: [links.map((l) => (0, import_jsx_runtime3.jsx)("a", { href: l.href, children: l.label }, l.href)), githubPublic ? (0, import_jsx_runtime3.jsx)("a", { href: githubHref, rel: "noreferrer noopener", children: "GitHub" }) : (0, import_jsx_runtime3.jsxs)("span", { className: "link-soon", title: "Repo goes public once circ-compiler is ready to share", children: ["GitHub ", (0, import_jsx_runtime3.jsx)("small", { children: "(soon)" })] })] }), (0, import_jsx_runtime3.jsx)(ThemeToggle, {})] }), license && (0, import_jsx_runtime3.jsx)("p", { className: "muted", children: license }), colophon && (0, import_jsx_runtime3.jsx)("p", { className: "muted colophon", children: colophon }), signature && (0, import_jsx_runtime3.jsx)("p", { className: "signature muted", children: signature })] });
  }

  // dist/components/SiteShell.js
  function SiteShell({ children, nav, footer }) {
    return (0, import_jsx_runtime4.jsxs)(import_jsx_runtime4.Fragment, { children: [(0, import_jsx_runtime4.jsx)(Nav, { ...nav }), (0, import_jsx_runtime4.jsx)("main", { children }), footer !== null && (0, import_jsx_runtime4.jsx)(Footer, { ...footer })] });
  }

  // dist/components/CodePreview.js
  init_define_import_meta_env();
  var import_jsx_runtime5 = __toESM(require_react_shim(), 1);
  function CodePreview({ title, source, preview, sourceLabel = "source", previewLabel = "circ-compile --preview", caption, approximate = false }) {
    return (0, import_jsx_runtime5.jsxs)("figure", { className: "cp", children: [title && (0, import_jsx_runtime5.jsx)("figcaption", { className: "cp-title", children: title }), (0, import_jsx_runtime5.jsxs)("div", { className: "cp-panes", children: [(0, import_jsx_runtime5.jsxs)("div", { className: "cp-pane cp-source", children: [(0, import_jsx_runtime5.jsx)("div", { className: "cp-pane-label", children: sourceLabel }), (0, import_jsx_runtime5.jsx)("pre", { children: (0, import_jsx_runtime5.jsx)("code", { children: source.trim() }) })] }), (0, import_jsx_runtime5.jsxs)("div", { className: "cp-pane cp-preview", children: [(0, import_jsx_runtime5.jsxs)("div", { className: "cp-pane-label", children: [previewLabel, approximate && (0, import_jsx_runtime5.jsx)("span", { className: "cp-approx", title: "Illustrative \u2014 not byte-for-byte CLI output", children: "approx." })] }), (0, import_jsx_runtime5.jsx)("pre", { children: (0, import_jsx_runtime5.jsx)("code", { children: preview.replace(/^\n+|\n+$/g, "") }) })] })] }), caption && (0, import_jsx_runtime5.jsx)("p", { className: "cp-caption", children: caption })] });
  }

  // dist/components/CommandSnippet.js
  init_define_import_meta_env();
  var import_jsx_runtime6 = __toESM(require_react_shim(), 1);
  var import_react2 = __toESM(require_react_shim(), 1);
  function CommandSnippet({ code, copyLabel = "Copy" }) {
    const [label, setLabel] = (0, import_react2.useState)(copyLabel);
    const [copied, setCopied] = (0, import_react2.useState)(false);
    const timer = (0, import_react2.useRef)(void 0);
    const copy = async () => {
      let ok = false;
      try {
        await navigator.clipboard.writeText(code);
        ok = true;
      } catch {
        ok = false;
      }
      setLabel(ok ? "Copied" : "Failed");
      setCopied(ok);
      clearTimeout(timer.current);
      timer.current = setTimeout(() => {
        setLabel(copyLabel);
        setCopied(false);
      }, 1500);
    };
    return (0, import_jsx_runtime6.jsxs)("div", { className: "install-snippet-wrap", children: [(0, import_jsx_runtime6.jsx)("pre", { className: "install-snippet", children: (0, import_jsx_runtime6.jsx)("code", { children: code }) }), (0, import_jsx_runtime6.jsx)("button", { type: "button", className: copied ? "copy-btn is-copied" : "copy-btn", "aria-label": "Copy command to clipboard", onClick: copy, children: (0, import_jsx_runtime6.jsx)("span", { className: "copy-btn-text", children: label }) })] });
  }

  // dist/components/LiveCanvas.js
  init_define_import_meta_env();
  var import_jsx_runtime7 = __toESM(require_react_shim(), 1);
  function LiveCanvas({ label = "live simulation", hint = "click input pins to toggle", launchLabel = "\u25B6 Run interactively", state = "idle", errorMessage, children }) {
    const mounted = state === "mounted";
    return (0, import_jsx_runtime7.jsxs)("div", { className: "lc", children: [(0, import_jsx_runtime7.jsxs)("div", { className: "lc-header", children: [(0, import_jsx_runtime7.jsx)("span", { className: "lc-label", children: label }), (0, import_jsx_runtime7.jsx)("span", { className: "lc-hint", children: hint })] }), !mounted && (0, import_jsx_runtime7.jsx)("button", { className: "lc-launch", type: "button", disabled: state === "loading", children: state === "loading" ? "Loading\u2026" : launchLabel }), mounted && (0, import_jsx_runtime7.jsx)("div", { className: "lc-mount", children }), state === "error" && (0, import_jsx_runtime7.jsx)("div", { className: "lc-error", children: errorMessage ?? "Could not load the live simulation." })] });
  }

  // dist/components/InstallLine.js
  init_define_import_meta_env();
  var import_jsx_runtime8 = __toESM(require_react_shim(), 1);
  function InstallLine({ href, children }) {
    return (0, import_jsx_runtime8.jsx)("a", { className: "install-line", href, children });
  }

  // dist/components/Tagline.js
  init_define_import_meta_env();
  var import_jsx_runtime9 = __toESM(require_react_shim(), 1);
  function Tagline({ children }) {
    return (0, import_jsx_runtime9.jsx)("p", { className: "landing-tagline", children });
  }

  // dist/components/Lineage.js
  init_define_import_meta_env();
  var import_jsx_runtime10 = __toESM(require_react_shim(), 1);
  function Lineage({ children }) {
    return (0, import_jsx_runtime10.jsx)("p", { className: "lineage", children });
  }

  // dist/components/StatusNote.js
  init_define_import_meta_env();
  var import_jsx_runtime11 = __toESM(require_react_shim(), 1);
  function StatusNote({ children }) {
    return (0, import_jsx_runtime11.jsx)("div", { className: "status-note", children });
  }

  // dist/components/AlphaWarning.js
  init_define_import_meta_env();
  var import_jsx_runtime12 = __toESM(require_react_shim(), 1);
  function AlphaWarning({ tag = (0, import_jsx_runtime12.jsx)("strong", { children: "Alpha software." }), children }) {
    return (0, import_jsx_runtime12.jsxs)("aside", { className: "alpha-warning", role: "note", children: [tag && (0, import_jsx_runtime12.jsx)("p", { className: "alpha-tag", children: tag }), children] });
  }

  // dist/components/ExampleCard.js
  init_define_import_meta_env();
  var import_jsx_runtime13 = __toESM(require_react_shim(), 1);
  function ExampleCard({ title, id, lede, children, sourcePath, sourceHref = "https://github.com/jeffersonmourak/circ-compiler/blob/main" }) {
    return (0, import_jsx_runtime13.jsxs)("article", { className: "example-card", id, children: [(0, import_jsx_runtime13.jsx)("h3", { children: title }), lede && (0, import_jsx_runtime13.jsx)("p", { className: "lede", children: lede }), children, sourcePath && (0, import_jsx_runtime13.jsxs)("p", { className: "source-link muted", children: ["Source:", " ", (0, import_jsx_runtime13.jsx)("a", { href: `${sourceHref}/${sourcePath}`, rel: "noreferrer noopener", children: sourcePath })] })] });
  }

  // dist/components/TourStep.js
  init_define_import_meta_env();
  var import_jsx_runtime14 = __toESM(require_react_shim(), 1);
  function TourStep({ step, title, id, prose, children }) {
    return (0, import_jsx_runtime14.jsxs)("section", { className: "tour-step", id: id ?? `step-${step}`, children: [(0, import_jsx_runtime14.jsxs)("h2", { children: [(0, import_jsx_runtime14.jsxs)("span", { className: "step-num", children: ["Step ", step, "."] }), title] }), prose && (0, import_jsx_runtime14.jsx)("p", { className: "tour-prose", children: prose }), children] });
  }

  // dist/components/DocsPage.js
  init_define_import_meta_env();
  var import_jsx_runtime16 = __toESM(require_react_shim(), 1);

  // dist/components/Prose.js
  init_define_import_meta_env();
  var import_jsx_runtime15 = __toESM(require_react_shim(), 1);
  function Prose({ children }) {
    return (0, import_jsx_runtime15.jsx)("div", { className: "docs-prose", children });
  }

  // dist/components/DocsPage.js
  function DocsPage({ title, description, headings = [], activeSlug, breadcrumb, children }) {
    return (0, import_jsx_runtime16.jsxs)("article", { className: "docs", children: [(0, import_jsx_runtime16.jsxs)("header", { className: "docs-header", children: [breadcrumb && (0, import_jsx_runtime16.jsx)("nav", { className: "docs-breadcrumb", "aria-label": "Breadcrumb", children: (0, import_jsx_runtime16.jsx)("a", { href: breadcrumb.href, children: breadcrumb.label }) }), (0, import_jsx_runtime16.jsx)("h1", { children: title }), description && (0, import_jsx_runtime16.jsx)("p", { className: "docs-lede", children: description })] }), (0, import_jsx_runtime16.jsxs)("div", { className: "docs-grid", children: [(0, import_jsx_runtime16.jsx)("aside", { className: "docs-toc", "aria-label": "On this page", children: (0, import_jsx_runtime16.jsxs)("nav", { children: [(0, import_jsx_runtime16.jsx)("p", { className: "toc-label", children: "On this page" }), (0, import_jsx_runtime16.jsx)("ol", { children: headings.map((h) => (0, import_jsx_runtime16.jsx)("li", { className: `toc-h${h.depth}`, children: (0, import_jsx_runtime16.jsx)("a", { href: `#${h.slug}`, className: h.slug === activeSlug ? "toc-active" : void 0, children: h.text }) }, h.slug)) })] }) }), (0, import_jsx_runtime16.jsx)(Prose, { children })] })] });
  }

  // dist/components/DownloadTable.js
  init_define_import_meta_env();
  var import_jsx_runtime17 = __toESM(require_react_shim(), 1);
  function DownloadTable({ rows, headers = ["OS", "Architecture", "File name", "Min OS version", "Download"] }) {
    return (0, import_jsx_runtime17.jsxs)("table", { className: "download-table", children: [(0, import_jsx_runtime17.jsx)("thead", { children: (0, import_jsx_runtime17.jsx)("tr", { children: headers.map((h) => (0, import_jsx_runtime17.jsx)("th", { children: h }, h)) }) }), (0, import_jsx_runtime17.jsx)("tbody", { children: rows.map((r) => (0, import_jsx_runtime17.jsxs)("tr", { children: [(0, import_jsx_runtime17.jsx)("td", { children: r.os }), (0, import_jsx_runtime17.jsx)("td", { children: r.arch }), (0, import_jsx_runtime17.jsx)("td", { children: (0, import_jsx_runtime17.jsx)("code", { children: r.file }) }), (0, import_jsx_runtime17.jsx)("td", { children: r.minVersion }), (0, import_jsx_runtime17.jsx)("td", { children: r.href ? (0, import_jsx_runtime17.jsx)("a", { href: r.href, children: r.linkLabel ?? "Download" }) : null })] }, `${r.os}-${r.arch}-${r.file}`)) })] });
  }
  return __toCommonJS(index_exports);
})();
window.CircDS=CircDS.__dsMainNs?Object.assign({},CircDS,CircDS.__dsMainNs,{__dsMainNs:undefined}):CircDS;
