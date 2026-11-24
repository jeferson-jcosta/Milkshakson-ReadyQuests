# Changelog - Milkshakson - Ready Quests

## 2.10.1
- Also hides **QuestMaster**'s and **EllesmereUI**'s quest trackers while the window is shown (Options > Tracker, one option each; optional, detected by frame name).
- New installs hide the other trackers (game, Questie, QuestMaster, EllesmereUI) by default while the window is shown. Existing settings are kept; the two new options start on for everyone.

## 2.10.0
- Options: "Buy me a coffee" moved to the top of the page, highlighted, with PayPal and PIX buttons that show the link ready to copy (addons can't open the browser). Shared UI library v8.
- Reward upgrade check now prefers stat weights over item level: **Pawn**, else **GearQuest Forever** (stat score for your spec), else item level. A higher item level with worse stats is no longer shown as an upgrade when one of those addons is installed. Configurable in Options > List (Auto / Pawn / GearQuest / Item level); a chosen addon that is not installed falls back to the next. The tooltip says which one decided (e.g. "GearQuest 80 > 50").
- Zone headers get a small grey **gryphon** (Alliance) or **wyvern** (Horde) when the zone has a flight point of your faction (or neutral) you haven't discovered yet. Hover: the list with distances; click: waypoint to the nearest (route with Shortest Path Forever / TomTom when installed). Game API only (`C_TaxiMap`). Option in Options > List (on by default). `/rq debug taxi` shows what the game reports.

## 2.9.4
- Ready dungeon quests turned in outside (Forever Dungeon Journal) are no longer listed "On this map" inside the dungeon just because the quest log files them under its name. If the game points at the dungeon, they are grouped by the turn-in place instead (Mythology of the Titans -> Ironforge), without a distance to the wrong spot.
- Dungeon quests still in progress show **Inside** (their objectives are in the dungeon) even when they are turned in outside, e.g. Mythology of the Titans and Past Due (book in Scarlet Monastery, turn-in in Ironforge / Dalaran). The tooltip says "Objectives inside the dungeon" and where the turn-in is. Once ready, the tag shows the turn-in side as before.

## 2.9.3
- Right-click menu: **LFM** (looking for more) when you are in a group that still has room. Posts the quest link and your group size (e.g. 3/5) in a chat channel you joined or /say. 30 s cooldown per channel.
- `/rq debug` output also opens in a copy window (Ctrl+A, Ctrl+C) and is saved in the SavedVariables, since the chat can't be copied.

## 2.9.2
- Clicking a quest now opens it on the map. "Go there" (route / waypoint) stays in the right-click menu.
- Class and profession quests get an icon (your class icon / the profession icon) and a tooltip line, when the game files them in the quest log under your class or one of your professions. Option to hide it.

## 2.9.1
- **Search**: magnifier button in the title bar opens a search box below the tabs (hidden by default). Filters every tab by quest name, objectives or zone (all words must match, case-insensitive). Esc or the button again closes and clears it; the magnifier turns yellow while a filter is active.
- Quest titles use the game's difficulty colour, as in the quest log: red/orange above you, yellow on level, green easy, grey trivial (per quest from the game, otherwise by level). Failed quests stay red.

## 2.9.0
- Quests with a usable item (torch, bottle, etc.) get a button on the right of their row to use it, with cooldown and charges, like the game's tracker. In combat the list keeps its layout while these buttons are shown (changes apply when combat ends), and scrolling/dragging waits for the end of combat.
- Distance and travel time on quest rows are now optional (Options > List, off by default); always in the tooltip, sorting unchanged.
- Resizing by the corner keeps the height you set (the window no longer shrinks back to the list), and the window stays pinned by its top-left corner, so it no longer re-centres vertically. Option "Shrink the window to fit the list" brings the old behaviour back.
- **Lock size** is a separate option (and `/rq lock size`): "Lock position" no longer hides the resize grip. Existing settings keep their behaviour (a locked window starts with its size locked too).
- Inside a dungeon, in a group: **Share** button in the window. Left-click shares this dungeon's quests, right-click every quest that can be shared (one per second). Also `/rq share` and `/rq share all`.
- Right-click menu: **Share with party** is always listed. When it can't be used it is greyed out with the reason (not in a group / the game says the quest can't be shared). Works with both the modern and the classic quest log API; prints a confirmation.
- Dungeon/raid quests in progress (game quest tag) are grouped under the dungeon the game files them under in the quest log (Uldaman, Scarlet Monastery), instead of the zone around the entrance (e.g. Loch Modan, Tirisfal Glades).
- Tooltip: the money reward is labelled "Money" / "Dinheiro" instead of "Gold" / "Ouro" (it can be silver or copper).

## 2.8.0
- Right-click menu: **Ask for help** on quests in progress. Posts the quest link and the objectives still missing in party/raid, any chat channel you joined (General, LookingForGroup...) or /say. 30 s cooldown per channel.
- Quest chains no longer use Questie. Sources: the game's quest lines (now asked with the quest's map), Forever Dungeon Journal's chains when that addon is installed (optional), and links learned while you play (the same NPC offers or gives you a quest right after you turn one in; kept per account).
- Chain shown with an icon instead of the word: icon + "2/5" when the whole chain is known, icon + "3" (step) for learned chains. Tooltip: step, "Comes after" / "Next".
- `/rq debug` shows the chain and its source (questline / fdj / learned) for every quest.

## 2.7.2
- Fix: quests whose turn-in is in a neighbouring zone were grouped under the wrong zone (e.g. Theramore quests under The Barrens). The POI now goes to the zone it actually sits in.
- `/rq debug` shows which map listed each quest.

## 2.7.1
- Dungeon quests show whether the turn-in is **Inside** or **Outside** the dungeon (tag and tooltip). Uses Forever Dungeon Journal's quest data when installed (it knows NPCs the map places at the entrance), otherwise the map at the turn-in spot.

## 2.7.0
- Tabs: **Ready**, **Active** (in progress, with objectives), **Zone** (quests of your current zone) and **All** (whole log by zone), with a quest count on each tab.
- Group headers collapse/expand with a click (remembered per tab).
- Switches to the Ready tab by itself when a quest gets completed (optional).
- Click an in-progress quest to route to its objective area (Shortest Path Forever / TomTom).
- Right-click menu on quests: go there, open on map, track/untrack, share with party, abandon.
- Options to hide Questie's tracker and the game's quest tracker while the window is shown.
- "Hide when empty" now means an empty quest log.
- `/rq tab ready|active|zone|all`.
- Collapse/expand button (+/-) like Questie's tracker; `/rq min`.
- Inside dungeons, distances are measured from where you entered, so the list keeps its order.
- The All tab shows quests/log size (e.g. 28/40).
- Moves below Forever Dungeon Journal's run tracker (bosses window) while it covers the window, and goes back when it closes.

## 2.6.2
- `/mrq debug` shows the saved options.

## 2.6.1
- Turn-ins inside dungeons/caves are found (dungeon/cave maps and your current map are scanned).
- Quest type tag from the game (`[Dungeon]`, `[Raid]`, `[Group]`).
- `/mrq debug` diagnostic command.

## 2.6.0
- Options panel (Options > AddOns > Milkshakson > Ready Quests).
- Turn-in place tags: `Dungeon` / `Cave`.
- Quest chain tag (`Chain 2/4`) from quest lines or Questie's database.
- "Buy me a coffee" section (PayPal / PIX).

## 2.5.0
- Reward item icons with the real item tooltip (Pawn and GearQuest lines show), Shift to compare, Ctrl-click preview.

## 2.4.0
- Reward tags: level up, XP, gold, item upgrades (Pawn or item level).
- Groups sorted by the easiest turn-in (travel time or distance), not always the current map first.

## 2.3.0
- Resizable window with scrolling.

## 2.2.0
- Grouped by turn-in location ("On this map" first), distance, Shortest Path Forever / TomTom integration, route through all turn-ins.

## 2.1.0
- English by default with language packs (ptBR included).

## 2.0.0
- Lists quests in the log that are ready to turn in.
