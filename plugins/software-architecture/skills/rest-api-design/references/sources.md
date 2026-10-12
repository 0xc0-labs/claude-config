# Sources

Every bracketed key in `SKILL.md`, `payload.md` and `examples.md` resolves
here. Links were fetched on 2026-10-12. Where a point says "no standard
decides this" or "org convention", none of these settles it.

## Standards

| Key | Source | What it backs |
|---|---|---|
| [RFC 9110] | R. Fielding, M. Nottingham, J. Reschke (eds.), "HTTP Semantics", RFC 9110, STD 97, June 2022. <https://www.rfc-editor.org/rfc/rfc9110.html> | 8.8.3 ETag; 9.2.1 safe and 9.2.2 idempotent methods; 9.3.x GET, HEAD, POST, PUT, DELETE; 10.2.1 Allow; 10.2.2 Location; 13.1.1 If-Match; 13.1.2 If-None-Match (incl. `*`); 15.x status codes. PATCH is not defined here |
| [RFC 9111] | R. Fielding, M. Nottingham, J. Reschke (eds.), "HTTP Caching", RFC 9111, STD 98, June 2022. <https://www.rfc-editor.org/rfc/rfc9111.html> | 4.3 validation; 5.2.2.1 max-age; 5.2.2.4 no-cache; 5.2.2.5 no-store; 5.2.2.7 private |
| [RFC 9457] | M. Nottingham, E. Wilde, S. Dalal, "Problem Details for HTTP APIs", RFC 9457, July 2023, obsoletes RFC 7807. <https://www.rfc-editor.org/rfc/rfc9457.html> | 3.1 members `type`, `title`, `status`, `detail`, `instance`; `about:blank`; 3.2 extension members; the `errors`/`pointer` example; relative `type` URIs; no implementation details in problems |
| [Idempotency draft], short [draft] | J. Jena, S. Dalal, "The Idempotency-Key HTTP Header Field", **draft-ietf-httpapi-idempotency-key-header-07**, IETF httpapi WG, 2025-10-15. An Internet-Draft, not an RFC; the datatracker shows it as expired. Datatracker: <https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/>; text: <https://www.ietf.org/archive/id/draft-ietf-httpapi-idempotency-key-header-07.html> | 2.1–2.2 syntax and uniqueness; 2.3 expiry; 2.4 fingerprint; 2.5.2 publish the policy; 2.6 replay the first result, 409 for concurrent; 2.7 errors 400, 409, 422 |
| [OpenAPI 3.1.2] | OpenAPI Initiative, "OpenAPI Specification v3.1.2", 2025-09-19. <https://spec.openapis.org/oas/v3.1.html> | The contract format; Schema Object based on JSON Schema Draft 2020-12 |

## Guidelines

| Key | Source | What it backs |
|---|---|---|
| [Zalando NNN] | Zalando, "RESTful API and Event Guidelines", rule NNN (living document, no edition number). <https://opensource.zalando.com/restful-api-guidelines/> | 100, 101, 192 API first and OpenAPI; 113–115 versioning; 118 snake_case; 129 kebab-case; 134 plural; 137 query parameters; 138 no actions; 150, 220 status codes; 151 document responses; 160 cursor; 161, 248 page object; 176 problem JSON; 182 ETag; 230 Idempotency-Key |
| [Microsoft] | Microsoft, "Microsoft Azure REST API Guidelines", `azure/Guidelines.md` on the `vNext` branch of microsoft/api-guidelines (latest change-history entry 2025-03-28). <https://github.com/microsoft/api-guidelines/blob/vNext/azure/Guidelines.md> | camelCase JSON; kebab-case paths; `api-version`; `value` + `nextLink`; JSON Merge Patch; conditional requests and hash ETags; `Repeatability-Request-ID` |

## Payload (checked against the 3.x docs; latest stable v3.90.2)

| Key | Source |
|---|---|
| [Payload REST] | REST API overview, incl. custom endpoints. <https://payloadcms.com/docs/rest-api/overview> |
| [Payload queries] | Querying, `where` operators. <https://payloadcms.com/docs/queries/overview> |
| [Payload sort] | Sort. <https://payloadcms.com/docs/queries/sort> |
| [Payload pagination] | Pagination. <https://payloadcms.com/docs/queries/pagination> |
| [Payload Local API] | Local API, `overrideAccess` default. <https://payloadcms.com/docs/local-api/overview> |
| [Payload multi-tenant] | Multi-tenant plugin. <https://payloadcms.com/docs/plugins/multi-tenant> |
| [Payload source] | Error body, `formatErrors` at tag v3.90.2. <https://raw.githubusercontent.com/payloadcms/payload/v3.90.2/packages/payload/src/utilities/formatErrors.ts> |
| Release | v3.90.2, 2026-09-23. <https://github.com/payloadcms/payload/releases/latest> |
