# Stage 15 readiness evidence

Checked on 2026-10-08 in the local development and test environments. Autonomy and email remain opt-in and off by default.

| Criterion | Evidence | Status |
| --- | --- | --- |
| State trajectory, provenance, replay, time decay and isolation | Automated RU/EN state and request specs; version-one revisions replay after version-two extraction | Passed locally |
| Jealousy, attraction, conflicting signals and request for space | Explicit statements record source IDs without assigning the user's feeling to the character; a later boundary suppresses older attraction context; a request for space blocks initiative until a new user message | Passed for the supported direct phrases |
| Concurrent initiative and email retry | Two simultaneous schedulers create one attempt and one outbox event; two delivery workers send one email | Passed locally |
| Email transport | A synthetic confirmation email to `stage15-smoke@example.test` reached local Mailpit through the configured SMTP transport | Passed locally; no external provider tested |
| Model behavior | One live Mistral smoke used identical return-after-pause context with reserved and poetic character bibles. Responses differed in voice. A second smoke with the conversation model yielded distinct warm and tense replies | Sample only; human review and a larger corpus needed |
| Initiative prevalence and quality | `/operations/metrics` reports the `NO_ACTION` share, sends and owner feedback. Owners can label a message helpful, irrelevant, repetitive or intrusive. Intrusive feedback disables both initiative channels. In a six-case synthetic quiet-character smoke, the decision model chose `NO_ACTION` six times; with an explicit invitation to follow up after an interview, it chose one low-intensity in-app message | Local smoke passed; no production sample yet |

The live model smoke exposed a limitation: one tense-context reply assumed the user looked tired and mentioned coffee without supporting context. The application rules were tightened to forbid unsupported visual and shared-location claims, and a repeat smoke no longer made either claim. A few samples still do not establish the no-invention criterion. Review real conversations and a human-labeled scenario set before considering Stage 15 fully accepted or enabling autonomy by default.

The direct phrase extractor intentionally misses indirect statements and cannot infer nuanced intent. It stores `none` for unsupported wording. False-positive state changes are treated as more costly than missed cues. Expand the vocabulary only with provenance and negative examples for roleplay, quotation, hypotheticals and third-party statements.
