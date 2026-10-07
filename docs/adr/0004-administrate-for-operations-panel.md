# 0004. Administrate for the operations panel

- Status: Accepted
- Date: 2026-10-07

## Context

Facet uses Rails 8.1, Propshaft, Importmap, and `tailwindcss-rails` without
Node.js in its production image. The administration panel must show operational
metadata across tenants while hiding messages, character bibles, memories,
provider errors, and secrets. Generic create, update, delete, export, and bulk
actions are unsafe for usage and workflow records.

We checked current alternatives before integration:

- ActiveAdmin 3 uses the older asset stack. ActiveAdmin 4 is still beta and its
  [upgrade guide](https://github.com/activeadmin/activeadmin/blob/master/UPGRADING.md)
  assumes `cssbundling-rails`, an npm package, and a separate Tailwind build.
- Avo 4 supports Propshaft, but its [authorization feature](https://docs.avohq.io/4.0/authorization-api.html)
  is an add-on. Facet needs explicit resource authorization regardless of the UI.
- RailsAdmin 4 ships prebuilt assets for Propshaft but remains beta as of this
  decision. Its default CRUD and export surface needs extensive restriction.
- Administrate 1.0 is stable, accepts Rails 8, and uses normal Rails controllers
  and views. A trial install on this app and a production asset build passed.

## Decision

Pin `administrate` to 1.0.0. Add only users, personalities, generation runs,
model calls, initiative attempts, and outbox events. Their dashboards contain
an explicit metadata field allowlist. Routes expose only index and show. The
overview shows counts, budget totals, and Sidekiq queue state. There are no
admin routes for messages, memories, character versions, login challenges,
exports, or bulk actions. A later extension adds explicit prompt-template and
provider-correction publication routes, each with revision history and audit.
The personality detail page displays only its current Character Bible as
escaped, read-only text; historical versions remain outside the admin UI.

The existing email-code login establishes a session, and every admin request
checks the current user's confirmed `admin` role on the server. The role can
only be assigned through an operator console. Admin reads and allowed actions
write an audit event with actor ID, action, target type and ID, and timestamp;
no private content is copied. Audit events expire after one year, or when the
actor account is deleted.

Write actions are disabling a personality's initiative, re-enqueuing an old
pending run, and publishing or restoring AI prompt revisions. No generic model
updates are exposed.

## Consequences

- The admin UI uses a maintained Rails dashboard library and the existing
  production asset pipeline.
- Adding a resource requires a deliberate route and dashboard allowlist.
- Tests must cover authorization, hidden fields, disabled CRUD, auditing, and
  the production asset build.
