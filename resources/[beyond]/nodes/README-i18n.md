# Web Atlas localization

The external Node Atlas follows the existing BeyondSurvival server language.
There is no separate panel language setting, browser-language detection or
language query parameter.

## Language source and catalogs

`NodesLocale.Current()` calls `BSLocale.Default()` from `bs_core`. The existing
core locale system resolves the configured server default; this resource does
not introduce another setting or change account language preferences.

Translations come from `bs_atlas/locales/<lang>.lua`. English is loaded first,
then the selected language overrides it. Existing supported languages are used
when their catalogs are available. The web-specific additions are complete in
English and German; other catalogs fall back to English for missing entries.

Catalogs are cached in memory. Reloading the page picks up the current server
language. After editing a catalog file, restart `nodes` to reload its contents.

## HTTP delivery

The existing HTTP handler builds the panel from `bs_atlas/html/` and embeds the
shared `bs_ui/html/js/i18n.js` library in place of its NUI-only script URL.
It embeds the initial locale and includes it in the boot response, so the
interface is translated before it opens, including boot failures.

`GET /nodes/api/i18n` returns `{ lang, dict }` as UTF-8 JSON with
`Cache-Control: no-store`. It uses the same existing panel-key/local-peer gate
as the panel and the other HTTP routes. Other methods return HTTP 405. The
route accepts neither a requested locale file nor an independent language.

Existing operation names, request payloads, response data fields and HTTP
status codes remain intact. Boot gains the additive `locale` field; the new
route exposes the same locale bundle. Human-readable errors, notes, rejected
configuration reasons and console hints are translated. Technical identifiers,
configuration keys, unknown error details and map data remain unchanged.

## UI coverage

The existing atlas catalogs now also cover web calibration controls, dialogs,
connection and authorization messages, configuration labels, terrain/noise
labels and vehicle states. Numbers and times use the active language. Longer
labels fit the existing tabs without horizontal clipping.

The in-game Atlas continues to use its existing account-language bridge.
Shared renderer changes only affect labels and locale formatting; simulation,
node editing, permissions and operation whitelists are unchanged.

## Validation

The implementation was checked with Lua and JavaScript syntax checks, an
isolated FiveM HTTP-handler harness, and browser checks in German and English.
Coverage includes all existing locale codes, English fallback, locale route
authentication, UTF-8/cache headers, existing mutation payloads and POST
requirements, map controls, confirmation dialogs, configuration editing and
calibration. Browser mutation requests were mocked rather than sent to a
running server.
