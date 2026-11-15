# Ani demo script

Four steps, about five minutes. Start on Home with language set to English (Settings > Change language). Crop names are Filipino in both languages (Palay, Sibuyas, Munggo, Mais, Kamote). Expected results are the ones asserted in `app/test/features/recommend_chapter5_test.dart` and `demo_replay_test.dart`, and match `python pipeline/planner.py`.

For steps 1-3 use these answers unless stated: **last two crops** Palay, Palay; **won't plant** nothing; **cold storage** off; **priorities** tapped in order Low risk, Saves water, Income. Open the questionnaire with **What should I plant?** on Home; each step has **Continue** (Back to return), the last has **See advice**. Use **Answer again** on the result to rerun with new answers.

## 1. Guimba, rainfed: Hold

| Question | Tap |
| --- | --- |
| 1 Which town is your farm in? | Guimba |
| 2 Last two crops | Most recent: Palay. The crop before that: Palay |
| 3 How much water can you give? | Water source: Rain only (optional). Irrigations: **Rain only (no irrigation)** |
| 4 Any crops you won't plant? | Leave all unticked; leave cold storage off |
| 5 What matters most? | Low risk, then Saves water, then Income ("3 of 3 picked"), then **See advice** |

Expected: no crop cards. The result is the Hold screen titled **Huwag munang magtanim**, with the reason "The chance of crop failure is too high for your water supply this El Niño", the five crops listed as ruled out, the tip to cover the soil with straw or let it rest and prepare irrigation, and **Kumonsulta sa MAO**. Say: with no irrigation in an El Niño the app declines to recommend anything rather than gamble.

## 2. Guimba, about 2 irrigations: Munggo

Tap **Answer again**, keep everything the same, but in step 3 choose **About 2 irrigations** (water source e.g. Pump or shallow tube well).

Expected: exactly one card, **Munggo** (mung bean), "Failed in 0 of 9 El Niño years", about 98 mm of water, income about 14,300 PHP (range 2,100 to 29,500) and the flag that the local market is small, so consult the MAO. Reason shown: the only crop that survives this season on about 2 irrigations. Say: same farm, a little water changes Hold to a concrete crop.

## 3. Bongabon, irrigate as needed: Sibuyas with a warning

Answer again: step 1 **Bongabon**; step 3 **Irrigate as needed**; everything else as above.

Expected: three cards, ranked Munggo, Kamote, **Sibuyas** (all five crops pass the safety checks; the top three by your priorities are shown). Sibuyas shows the flag **No cold storage: high price risk** (Walang cold storage: mataas ang panganib sa presyo) with the highest income estimate (about 726,000 PHP per hectare, wide range). Optional: go back to step 4, tick **I can use cold storage**, and the Sibuyas warning disappears (the guard is soft). Say: the app shows the upside and the risk together and leaves the choice to the farmer.

Note: the ranking above is for the priority order in this script; other orders reorder the cards but Sibuyas always stays on the list with its warning (tested for four priority orders and for both Guimba and Muñoz).

## 4. Track a planting via the replay demo

Open the **My farm** tab and tap the **Season replay (demo)** card (also in Settings). The banner "Replay of a past season – not live data" stays on screen throughout.

1. Pick a past season, for example **Palay in Guimba** (dry season 2023-24). The replay opens at **Day 0**, stage **Prep**.
2. Tap **Next day** (Day 1), then **+7 days** (Day 8). Watch the stage and the water and heat alerts update; demo alerts are tagged **Demo**.
3. Tap **Run to end**. If a harvest is ready, tap **Confirm harvest** when offered. The screen shows **Replay finished** with the season outcome.
4. Tap **Start over** to reset to Day 0, or go back and open the other two seasons (Sibuyas in Muñoz 2004-05, rainfed; Sibuyas in Bongabon 2011-12, 4 irrigations). Together the three replays show every alert type.

Expected: "Alerts from the replay are not saved and do not notify you." Nothing is written to My farm, and no notification permission is requested. To track a real crop instead, use **Track this crop** on a result card, or **Add planting** on My farm.

## Checks before presenting

- `cd app && flutter test test/features/recommend_chapter5_test.dart test/features/demo_replay_test.dart`
- `python pipeline/planner.py --muni guimba --water rainfed --last rice rice --priorities risk water income` (Hold), then `--water limited_2` (Munggo), and `--muni bongabon --water full` (Munggo, Kamote, Sibuyas with the cold-storage warning).
- Airplane mode: everything above works offline; only the live Outlook top-up needs a connection.
