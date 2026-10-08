# Stage 15 baseline and behavior contract

Captured on 2026-10-08 before enabling dynamic state for any personality. The local development database has 5 personalities, 1 completed initiative attempt, 0 skipped or failed attempts, and 0 unread initiative messages. This is a development fixture baseline, not a production quality sample. The pre-stage-15 initiative path was opt-in and used a 12–168 hour idle interval and 24–720 hour cooldown. It had no quiet hours, daily or weekly budget, or recorded `NO_ACTION` decision. These baseline counts precede the new policy and should not be interpreted as quality measurements.

## Observable trajectories

| Situation | Confirmed input | Permitted state movement | Initiative boundary |
| --- | --- | --- | --- |
| Growing trust | Direct user statement of trust | Trust rises slowly; warmth rises briefly | No new initiative from this event alone |
| Conflict | Direct statement of anger toward the character | Trust falls slightly, tension rises, irritation rises briefly | Never send a confrontational follow-up from a single event |
| Repair | Direct apology | Tension falls and warmth can rise | No automatic demand for further apology |
| Closeness | Direct statement of liking time together | Closeness rises slowly; warmth rises briefly | No automatic romantic or sexual escalation |
| Jealousy or sexual tension | Explicit context with a clear boundary | No numeric update in v1; retain grounded conversation context | No autonomous action in slice 15.1 |
| Long pause | Passage of time only | Fast emotion decays; durable trust, closeness and tension remain | Silence is never evidence of rejection |
| Return after pause | New confirmed message | Apply the new event after decay | Do not infer feelings from absence alone |
| Switch threads | Same personality, another thread | Use the same per-personality state | Do not copy state to another personality |

The first extractor accepts only narrow, direct statements in Russian and English. Roleplay marked with asterisks, questions and hypothetical statements produce a recorded `none` observation. It intentionally misses indirect cues; false positive relationship changes are more costly than missed changes. Every observation stores its exact extractor result, source message ID and rule version, so replay does not depend on another model call. If a model extractor replaces it, its response must be stored before applying the deterministic rules.

`trust`, `closeness` and `tension` are independent values from 0 to 100. `warmth` and `irritation` are independent fast values; their half-lives are 24 and 8 hours. The values are implementation state, not claims about the user's feelings or a model's real feelings. No numeric value enters the ordinary UI in slice 15.1. Initiative remains controlled by its existing setting until the separate policy in slice 15.3.

Compare counts of `NO_ACTION` decisions, completed sends, unread sends, unanswered sends, repeated motives, user disables, and complaints over equal time windows. The operations metrics endpoint now reports decision counts and completed sends. User feedback and false initiatives still require a human-labeled review set; a single local completed attempt cannot establish their rate.

The first external channel is email. It requires a separate owner opt-in and uses the same quiet hours and decision policy. An email decision creates an in-app copy. Delivery audit distinguishes pending, sending, delivered, failed, suppressed, and unknown outcomes; an unknown SMTP outcome is never automatically resent because SMTP does not provide an end-to-end deduplication guarantee.
