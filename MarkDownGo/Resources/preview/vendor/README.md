# Vendored preview assets

All bundled offline so the preview never touches the network.

| Library | Version | License | Files |
|---|---|---|---|
| [KaTeX](https://katex.org) | 0.16.11 | MIT | `katex/katex.min.css`, `katex/katex.min.js`, `katex/auto-render.min.js`, `katex/fonts/*.woff2` |
| [Mermaid](https://mermaid.js.org) | 10.9.5 (UMD) | MIT | `mermaid/mermaid.min.js` |

Why Mermaid 10.9.5: `mermaid@11`'s `dist/mermaid.min.js` is an esbuild ESM bundle
(`__esbuild_esm_mermaid_nm`) that expects a module loader. The preview loads assets over a
custom `mdg-preview://` URL scheme, where ES module resolution is unreliable; 10.9.5 ships a
classic UMD build that a plain `<script>` tag consumes. Upgrade when the preview moves to a
real origin (e.g. `WKWebView` with an HTTP server) or mermaid ships UMD again.
