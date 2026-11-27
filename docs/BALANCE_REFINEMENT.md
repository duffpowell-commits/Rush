# Rush 8.5 refinement — Nov 27, 2026

Input: independent [build 106 playtest](reviews/firsttimer_rush_build106.md) — 8/10;
37/37 served in four services, A+ each, zero walks. Duff approved challenge,
economy, specialization, action clarity and mobile readability as one pass.

## Changes

- Chef Challenge is earned inside the saved night. A+ from service 2 adds a level
  (cap 3, TUNE); D/F eases one, a loss eases two. One added table per level from S3
  in Normal/Slammed, an extra large table from S4 at challenge 2+. Relaxed ignores
  and does not build bonus pressure. Original onboarding and $45 Jo are unchanged.
  Grade and tonight sheets explain extra load; save v8 migrates older nights to
  neutral pressure, without changing any current saved ticket.
- Prices: Family Meal $35, Heat Lamps $40, Cast Iron $65 (opens S3),
  Second Chance $70 (opens S4). Server Tray $30, Entree Tray $65, station burners
  $100 and Jo $45 unchanged. Existing ownership stays. No purchase-driven extra tickets.
- Primary-role advanced perk available for the next pick after two earned perks
  and S4 opens: Heat Master (specialty pan burn grace), Pass Captain (first batched
  RUN calms the cook), Deep Rest (4 stress recovered while idle), Long Stride (first
  2+ stop move saves 2 actions). One advanced role perk per cook, optional alongside
  other choices. Benefits reward specific tactics instead of another blanket action.
- Free actions remain usable at zero paid moves, but not on a break; one shared
  allowance per turn. 0+ badge, explicit RUSH 0 STRESS and REST -N IF IDLE labels.
  Paid actions cannot spend negative AP. Active pan grace/captain status are saved,
  including undo.
- Compact feedback/coach/caption strip in the gap between NEXT and stations, event
  line below crew, always-visible stress. Swipe crowded rail, tap ALL to inspect
  every order and upcoming demand; select a hidden ticket from the scrollable sheet.

## Automated comparative balance results

31,830 simulated service attempts, using the game's actual rule classes:
22,560 fixed-inventory attempts and 9,270 attempts across 1,680 campaigns, 240
paired seeds each. Campaigns buy by fixed priorities, select available perks,
apply adaptive pace, and stop at first loss (no retry). Greedy rule bot, not
a human or optimal specialist. Fixed inventories include hypothetical combinations.

| Configuration | S3 | S4 | S5 | S7 | S8 |
|---|---:|---:|---:|---:|---:|
| Jo alone, no chef challenge | 92% | 86% | 72% | 32% | 20% |
| Jo alone, maximum challenge | 62% | 32% | 20% | 4% | 1% |
| Jo + basic kit, no challenge | 95% | 92% | 80% | 45% | 25% |
| Jo + basic kit + advanced roles, maximum challenge | 98% | 88% | 77% | 53% | 45% |
| Jo + every shop item, no challenge | 100% | 100% | 98% | 95% | 90% |
| Jo + every shop item, maximum challenge | 99% | 95% | 90% | 82% | 72% |

Maximum challenge at S3 is a deliberately artificial stress test, not reachable
from normal fresh-night progression. Basic kit means Jo, Meal, Lamps, Server Tray,
Cast Iron. Advanced sample: Dev Heat Master, Mo Long Stride, Jo Pass Captain
with their prerequisite base perks. Starting service (neutral load, no upgrades)
still clears 93% across the fixed seeds.

| Normal campaign buying priority | Build 106 S8 | Refinement S8 |
|---|---:|---:|
| Jo first | 71% | 50% |
| Heat Lamps first | 70% | 55% |
| Basic equipment first | 65% | 49% |
| Trays first | 52% | 38% |

Pace comparison, Jo-first: Relaxed 95%, Normal 50%, Slammed 11% cleared S8;
the previous Normal Jo-first result was 71%. Starting tutorial unchanged.
Among Jo-first S2 survivors, median remaining cash was $22, and S4 $29;
all shop items are still reachable later. Trays-first is weaker in the greedy
bot; deliberate batch routing is not well modeled. The reviewer in build 106
found trays useful. Do not conclude that human players should never buy trays.

Reproduce with `XDG_DATA_HOME=$(mktemp -d) godot --headless --path . --script tools/balance_sweep.gd`.
The recorded relaxed campaign tracked pressure internally without applying it;
the final rule also avoids building that invisible pressure, so the effective
Relaxed schedule is identical. CSVs go to the isolated user data directory.

## Evidence

- 57 rule tests; old saves, advanced perk behavior, free actions at zero, pressure
  cap/relief and persistence.
- Rendered autoplay includes ZERO AP, RAIL PAGE, ADVANCED PERK, CHEF CHALLENGE passes.
- [Order overview](renders/flow_all_orders.png), [Free at zero](renders/flow_free_at_zero.png),
  [Advanced pick](renders/flow_advanced_pick.png), [Compact hint](renders/flow_refinement_hint.png).
- New independent blind first-timer review after deployment; never claim a human score.
