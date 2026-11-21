# Ready Quests (WoW: Forever)

A quest tracker for WoW: Forever, built around what is ready to turn in. Tabs for quests ready to turn in, quests in progress (with objectives), your current zone and the whole log. Updates automatically.

## Install
1. Close the game.
2. Copy the `Milkshakson-ReadyQuests` folder to `World of Warcraft\_forever_\Interface\AddOns\`.
3. Enable **Milkshakson - Ready Quests** on the AddOns screen.

## Usage
| Command | Action |
|---|---|
| `/rq` (or `/mrq`, `/readyquests`, `/entregar`) | Show/hide the window. Every `/rq` command also works as `/mrq` |
| `/rq list` | List in chat |
| `/rq lock` | Lock/unlock position |
| `/rq lock size` | Lock/unlock size (hides the resize grip) |
| `/rq auto` | Toggle "hide when the quest log is empty" (default: on) |
| `/rq reset` | Reset window position and size |
| `/rq lang <code\|auto>` | Set language (e.g. `/rq lang ptbr`, `/rq lang enus`, `/rq lang auto`) |

| `/rq min` | Collapse/expand the window (also the +/- button at its top-left) |
| `/rq tab <ready\|active\|zone\|all>` | Switch tab (also `prontas`, `andamento`, `zona`, `todas`) |
| `/rq route` | Plan one journey through every turn-in (Shortest Path Forever) |
| `/rq route here` | Same, only turn-ins on the current map |

- Quests are grouped by turn-in zone. Groups are sorted by **the easiest turn-in**: travel time with Shortest Path Forever, otherwise straight-line distance. A turn-in in the next zone can come before "On this map" when it is closer. Inside each group, quests are sorted the same way. Distance/travel time on the rows is optional (off by default; always in the tooltip); quests with a usable item get a button on the right to use it, like the game's tracker.
- **Click**: plan a journey to the turn-in. This uses Shortest Path Forever if installed, otherwise a TomTom waypoint, otherwise it super-tracks the quest.
- **Right-click**: open the quest on the map.
- **Shift-click**: insert the quest link in chat.
- **Route** button (left-click: all quests, right-click: this map only): one journey with nearest-first stops. Quests turned in at the same spot become one stop.
- Drag to move. Drag the bottom-right corner to resize: the window keeps the width and height you set (the option "Shrink the window to fit the list" makes it shrink to the list again, up to that height). The window is pinned by its top-left corner. The mouse wheel scrolls when the list is longer. `/rq lock size` (or the "Lock size" option) hides the grip; `/rq lock` only locks the position.

## Tabs
- **Ready**: quests ready to turn in, easiest turn-in first (distance, travel time, rewards).
- **Active**: quests in progress with their objectives (`Wolves slain: 4/8`), nearest first.
- **Zone**: only the quests of the zone you are in, ready ones first.
- **All**: your whole log, grouped by zone.

Type in the search box (below the tabs) to filter every tab by quest name, objectives or zone; Esc clears it. Click a group header to collapse it. Right-click a quest for a menu (go there, map, track, share, ask for help, abandon). Inside a dungeon, in a group, a **Share** button shares this dungeon's quests (right-click: every shareable quest); `/rq share [all]`. **Ask for help** posts the quest link and what is still missing in party/raid, a chat channel you joined (General, LookingForGroup...) or /say. The window can replace Questie's tracker: see the Tracker options.

## Options
Options > AddOns > **Milkshakson > Ready Quests**, or `/mrq config` (also `/rq config`), or right-click the addon button next to the minimap. From there you can:
- Show, auto-hide, lock the position and lock the size of the window, and set its width and maximum height.
- Toggle the rewards, dungeon/cave and chain indicators.
- Start a route.
- Pick the language.

## Turn-in place and chains
| Tag | Meaning |
|---|---|
| `Dungeon` (orange) | The turn-in spot is inside an instance |
| `Cave` (tan) | The turn-in spot is inside a cave or a building interior |
| chain icon + `2/4` | The quest is step 2 of a 4-step chain (just `3` = step 3, length unknown); the tooltip names the previous and next quest |

The place comes from the map at the turn-in spot. Chains come from the game's quest lines, from Forever Dungeon Journal's chains when it is installed, and from what you play: when an NPC gives you a quest right after you turn one in to it, the two are linked (remembered for all your characters). Questie is not used.

## Reward indicators
Each row shows compact tags:

| Tag | Meaning |
|---|---|
| `Lv+` (green) | Turning this quest in levels you up |
| `XP` (blue) | Gives XP (hidden at max level) |
| gold coin | Gives gold |
| item icons | Each item reward and choice (up to 4, upgrades first). A green arrow marks an upgrade; red means you can't use it |

**Hover an item icon** to see the game's own item tooltip. Lines added by Pawn and GearQuest Forever show up there, such as Pawn's stat score and GearQuest's slot ranking. Hold **Shift** to compare with your equipped gear. **Shift-click** links the item in chat; **Ctrl-click** opens it in the dressing room.

The header shows `+N Lv` when turning in everything would level you up. N is an estimate based on the size of your current level.

The tooltip lists everything: XP amount and % of a level, gold, each item and choice with its upgrade reason, and currencies.

Upgrade check: with **Pawn** installed, its verdict is used. Otherwise the addon compares item level with the weakest item equipped in that slot (an empty slot counts as an upgrade) and never suggests a lighter armor type than the one you wear in that slot.

## Integrations (optional)
- **Shortest Path Forever**: uses its public API (`ShortestPathForever.API`): `Estimate` for travel time and `NavigateRoute` for journeys, with `kind = "turnin"` and `handins`.
- **TomTom**: used for waypoints when Shortest Path Forever is not installed.
- **Pawn**: used for upgrade detection (the green arrow), and its tooltip lines show when you hover an item.
- **GearQuest Forever**: it has no public API, so its slot-ranking line shows in the item tooltip when you hover a reward icon.

## Languages
The default language is English. With `auto` (the default), the addon follows your game client's language when a pack for it exists.

Included packs:
- `enUS`: English (required)
- `ptBR`: Português (Brasil)

### Adding a language pack
1. Copy `Locales/enUS.lua` to `Locales/<code>.lua`, e.g. `deDE.lua`, `esES.lua`, `frFR.lua`.
2. Change the first line to `ns:NewLocale("deDE", "Deutsch")`.
3. Translate the strings and keep the `%d`/`%s` placeholders. If you leave a key out, the English text is used.
4. Add `Locales\deDE.lua` to `Milkshakson-ReadyQuests.toc`, below `Locales\enUS.lua`.

To remove a pack, delete its line from the `.toc`.

## Support / Apoie
If you enjoy the addon, you can buy me a coffee. The same links are in the in-game options panel, in copyable fields.
- **PayPal:** [Donate](https://www.paypal.com/donate/?business=Q72ZP8CCJ6PFA&no_recurring=0&item_name=Buy+me+a+coffee+to+keep+my+WoW+Forever+addons+updated%21+%2F+Me+pague+um+caf%C3%A9+e+ajude+a+manter+os+addons+atualizados%21&currency_code=BRL)
- **PIX (Brasil):** `2d8f2ae7-76df-497d-9afa-cb7d12dd73f9`
