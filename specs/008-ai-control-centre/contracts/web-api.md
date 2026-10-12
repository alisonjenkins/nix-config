# Contract: web view (loopback only)

`claude-monitor serve` — FR-030, FR-031. Same data and actions as the TUI. Server-rendered HTML for humans; the same routes return JSON when `Accept: application/json`.

## Security rules (testable)

1. Bind address is `127.0.0.1` (and `::1`). Never `0.0.0.0`; `--bind` accepts only `127.0.0.1` or `::1` and the parser refuses anything else.
2. Requests whose `Host` header is not `127.0.0.1:<port>`, `localhost:<port>` or `[::1]:<port>` get `421`.
3. Every route except `/` requires the token: first as `?token=` in the URL printed by `serve`, which the server answers with a `Set-Cookie: cc_token=…; HttpOnly; SameSite=Strict; Path=/` and a redirect that strips it; afterwards by that cookie. Missing/wrong → `401`.
4. State-changing routes (`POST`) additionally require header `X-CC-Token` equal to the cookie value (CSRF).
5. The token is 256 bits from the OS RNG, stored in `<state-dir>/web.token` (0600), rotated on each `serve` start.
6. No CORS headers; `Cache-Control: no-store`; no third-party assets (no CDN scripts or fonts).
7. No route returns raw conversation transcripts. Task description, left-off text, notes and summaries are returned.

## Routes

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | The overview and the projects page in one tree: a cross-project "Waiting on you" band, then one collapsible node per project (Active, Interrupted, Finished, nested collapsed Done), a "No project" node, collapsed Unseen, Dismissed behind its toggle. Each session row has a Move control (existing project dropdown or a new project). `Accept: application/json` adds `projects:[{id,name,status,summary,counts,progress?,sessions}]` and `no_project:{summary,counts,sessions}` beside the flat `sessions` list |
| GET | `/events` | SSE stream pushed from the change feed (research D12), no server polling loop: each message is `id: <events.seq>` and `data: {"changed":[{"entity":"session","id":"…","kind":"state"}]}` with exactly what changed. `Last-Event-ID` resumes from that `seq` after a dropped connection, so no change is missed. A `: keepalive` comment every 25 s keeps proxies and the connection open. |
| GET | `/sessions?state=&agent=&repo=&project=&text=&include_dismissed=` | Filtered list |
| GET | `/sessions/{id}` | Detail: progress with source label, lineage, notes, summaries |
| POST | `/sessions/{id}/respawn` | Body `{"fresh":false}`; returns outcome per FR-012 |
| POST | `/respawn` | Body `{"ids":[…]}` or `{"all_interrupted":true,"except":[…]}` (FR-010, FR-033) |
| GET | `/restore[?session=ID]` | Interrupted list with checkboxes (default all selected); `?session=` previews one session in any state with its refusals and alternatives. The overview and session-page Respawn buttons link here instead of starting immediately |
| POST | `/sessions/{id}/{park,unpark,undismiss}` | Markers (reversible, no confirmation) |
| GET/POST | `/sessions/{id}/dismiss`, `/projects/{id}/dismiss`, `/sessions/{id}/unlink` | Need an explicit confirmation: `POST` without `confirm` (`1`, `true`, `on`, `yes`) returns `409` `confirmation_required` and changes nothing; `GET` returns the question (JSON `{ok,confirmation_required,action,consequence,confirm_with}`, an inline panel fragment for `HX-Request`, else a page); `unlink` takes `?cortex=N` |
| POST | `/projects/{id}/{park,unpark,undismiss,summarize}` | Same markers and summary for projects |
| POST | `/sessions/{id}/{done,undone}` | Mark done / return to Finished; `done` on a non-finished session returns `409` with the reason |
| GET | `/projects/{id}` | Includes the project's own Done section below Active, Interrupted and Finished |
| POST | `/sessions/{id}/note`, `/projects/{id}/note` | Notes |
| POST | `/sessions/{id}/progress-source` | Choose among candidates (FR-015a) |
| POST | `/sessions/{id}/summarize` | On-demand model summary |
| GET/POST | `/projects`, `/projects/{id}` | `GET /projects` redirects (302) to `/` for pages and returns the project list as JSON; `/projects/{id}` is the focused single-project node; POST for rename, status and grouping (`POST /sessions/{id}/group` creates a missing project, `-` ungroups) |
| GET | `/links` | Cortexiphan links with disagreements highlighted |

Respawn responses: `200 {"started":[…],"refused":[{"id","code","message"}]}`; codes as in `data-model.md`. A refusal is not an HTTP error.

## Parity

A test enumerates the TUI actions and the routes above; adding an action to one without the other fails the build (SC-011).
