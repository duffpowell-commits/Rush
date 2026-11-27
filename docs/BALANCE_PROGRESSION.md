# Kitchen Progression & Balance — Nov 27, 2026

Approved follow-up to the build 104 balance review. Goal: keep the $45 Jo unlock, make
equipment a meaningful choice, smooth the service ramp, and give each cook a distinct earned role.

## Rules

- Services 1–3 use the original ticket schedule. Normal, neutral-house loads are now 7, 8, 9,
  10, 11, 12, 13, 14 across services 1–8. A second large table begins in service 7. Both late
  settings are tunable; the existing adaptive house and pace modes still apply.
- Shop purchases do not increase tickets. Entree Tray ($65) and individual Grill, Fry, Saute
  and Cold Burners ($100 each) become available for service 4. Each Burner doubles only its
  station. Cast Iron covers the stress of the kitchen's first rush per turn, not its AP.
- All permanent cooks (including Jo) earn productive work XP in completed services.
  One MVP chooses from three deterministic options, including a choice in their existing role
  when available. First perk names the role; later choices can diversify. XP is cumulative
  productive work, level is earned perk count + 1. Movement and RUSH don't farm XP.
- Each cook has one shared free-action allowance per turn. Station specialists speed longer
  dishes and can plate one-minute dishes free; Veteran perks improve rest or burn stress;
  Utility gets free PREP once that event opens. Pause -> CREW lists levels, roles, XP, perks.
- Save v7 preserves old equipment, earned perks and active kitchen state. Paid global burners
  map to all four station upgrades. New XP begins at zero for legacy saves (past work was not
  recorded separately). Cast Iron's allowance, station purchases and active work save/undo.

## Comparative test results

Godot 4.7.2, using the actual Kitchen and Upgrades rule classes, 240 paired seeds per scenario.
68,880 fixed-inventory service attempts, 7,270 service attempts in 1,200 normal campaigns,
plus 4,267 service attempts in 720 pace campaigns. The campaign model buys according to
fixed priority lists, picks available perks, applies adaptive difficulty, and stops on loss
(no retry). An isolated fixed inventory can be hypothetical; campaign purchases obey gates.
Completion means surviving the service, not an A grade. The greedy bot is not a human or
optimal tray specialist; these are comparative measurements, not player win-rate targets.

| Scenario | S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Normal, no upgrades | 93% | 76% | 52% | 34% | 13% | 3% | 0% | 0% |
| Jo only | — | 95% | 92% | 86% | 72% | 60% | 32% | 20% |
| Jo + Grill Burners | — | 100% | 99% | 98% | 92% | 85% | 57% | 40% |
| Jo + every shop item | — | 100% | 100% | 100% | 98% | 98% | 95% | 90% |

The build-104 Jo-only rates in S5/S7 were 86%/72%; Jo + the old global Double Burners
were 96%/92%. The revised curve leaves the onboarding baseline unchanged but asks players
to keep growing their kitchen. Fully equipped play still benefits strongly from progression.

| Campaign priority | Build 104 S8 | Revised S8 |
|---|---:|---:|
| Jo first | 78% | 71% |
| Heat Lamps first | 78% | 70% |
| Cheap equipment first | 63% | 65% |
| Trays first | 59% | 52% |
| No shop | 12% | <1% |

In the intermediate tuning pass, the ungated maximum tray first stranded players and
only 45% reached the end of S8; delaying the advanced tray to S4 raised the final result to
52% even with harder late orders. Early tray purchase is still the weaker tested route.
A human deliberately batching plates may get more value; don't interpret the greedy
bot as proof that the tray is worthless. Jo and Heat Lamps first are close, and cheap
equipment first is competitive. No-shop is deliberately not a viable late-game strategy.

In build 104, all surviving Jo-first campaigns owned every item after S5. In the revised
campaign, none did; median remaining cash was $48 after S5, $279 after S8 (previously
$170/$689). All surviving Jo-first campaigns had the full store by the end of S8.

Pace campaign (Jo-first, 240 starts each): Relaxed 93%, Normal 71%, Slammed 18% clear S8.
Slammed remains intentionally demanding; its S1 clear rate was 39% vs 90% Normal.

## Tests and next playtest

- Rule suite: 55 passing tests, including new save migration, station gating, shared allowance,
  productive XP/Jo MVP, specialist quick plate, Veteran stress and Cast Iron persistence.
- Visual autoplay: CREW PROGRESSION PASS, STATION SHOP PASS, and the existing full flow.
- Screens: [Crew](renders/flow_crew_progression.png), [Level-up](renders/flow_levelup.png),
  [Shop](renders/flow_station_shop.png). The advanced shop fits HUGE text with scrolling.
- Reproduce the normal sweep from the project with:
  `XDG_DATA_HOME=$(mktemp -d) godot --headless --path . --script tools/balance_sweep.gd`.
  It writes services and campaign CSVs to its isolated user data directory.
- Next: real phone playtest of an equipment-first and tray-first run, collect player feedback
  on grade pressure, perk choices and whether the advanced tray is worth its price.
  No human or blind first-timer rating is claimed here.
