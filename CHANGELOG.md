# Changelog - Milkshakson - Ready Quests

## Unreleased
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
