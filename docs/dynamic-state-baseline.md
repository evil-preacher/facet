# Stage 15 baseline and behavior contract

Captured on 2026-10-08 before enabling dynamic state for any personality. The local development database has 5 personalities, 1 completed initiative attempt, 0 skipped or failed attempts, and 0 unread initiative messages. This is a development fixture baseline, not a production quality sample. The pre-stage-15 initiative path was opt-in and used a 12–168 hour idle interval and 24–720 hour cooldown. It had no quiet hours, daily or weekly budget, or recorded `NO_ACTION` decision. These baseline counts precede the new policy and should not be interpreted as quality measurements.

## Observable trajectories

| Situation | Confirmed input | Permitted state movement | Initiative boundary |
| --- | --- | --- | --- |
| Growing trust | Direct user statement of trust | Trust rises slowly; warmth rises briefly | No new initiative from this event alone |
| Conflict | Direct statement of anger toward the character | Trust falls slightly, tension rises, irritation rises briefly | Never send a confrontational follow-up from a single event |
| Repair | Direct apology | Tension falls and warmth can rise | No automatic demand for further apology |
| Closeness | Direct statement of liking time together | Closeness rises slowly; warmth rises briefly | No automatic romantic or sexual escalation |
| Jealousy or attraction | Direct user statement | Record the user's statement with provenance, without a numeric change or inferred character feeling | No automatic sexual or romantic escalation |
| Changed feelings | Direct user statement that attraction or jealousy has ended | Record the new boundary and stop carrying the earlier feeling into the current prompt | No revival of earlier romantic context |
| Request for space | Direct user request | Record the boundary without a numeric change | Suppress autonomous initiative until the user speaks again |
| Long pause | Passage of time only | Fast emotion decays; durable trust, closeness and tension remain | Silence is never evidence of rejection |
| Return after pause | New confirmed message | Apply the new event after decay | Do not infer feelings from absence alone |
| Switch threads | Same personality, another thread | Use the same per-personality state | Do not copy state to another personality |

The version-two extractor accepts only narrow, direct statements in Russian and English. Roleplay marked with asterisks, questions and hypothetical statements produce a recorded `none` observation. It intentionally misses indirect cues; false positive relationship changes are more costly than missed changes. Every observation stores its exact extractor result, source message ID and rule version, so replay does not depend on another model call. Earlier version-one revisions remain replayable. If a model extractor replaces it, its response must be stored before applying the deterministic rules.

`trust`, `closeness` and `tension` are independent values from 0 to 100. `warmth` and `irritation` are independent fast values; their half-lives are 24 and 8 hours. The values are implementation state, not claims about the user's feelings or a model's real feelings. No numeric value enters the ordinary UI in slice 15.1. Initiative remains controlled by its existing setting until the separate policy in slice 15.3.

Compare counts of `NO_ACTION` decisions, completed sends, unread sends, unanswered sends, repeated motives, user disables, and complaints over equal time windows. The operations metrics endpoint reports decision counts, the `NO_ACTION` share, completed sends, and owner feedback. `irrelevant` and `unwelcome` are owner-reported signals of a false or intrusive initiative; an `unwelcome` report also disables in-app and email initiative immediately. Feedback is optional, so these counts are not an unbiased false-initiative rate. A human-labeled review set and production observation are still needed to establish quality, distinct character behavior and the feeling of continuity.

The first external channel is email. It requires a separate owner opt-in and uses the same quiet hours and decision policy. An email decision creates an in-app copy. Delivery audit distinguishes pending, sending, delivered, failed, suppressed, and unknown outcomes; an unknown SMTP outcome is never automatically resent because SMTP does not provide an end-to-end deduplication guarantee.
