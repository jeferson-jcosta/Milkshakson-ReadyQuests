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
| `/rq auto` | Toggle "hide when the quest log is empty" (default: on) |
| `/rq reset` | Reset window position and size |
| `/rq lang <code\|auto>` | Set language (e.g. `/rq lang ptbr`, `/rq lang enus`, `/rq lang auto`) |

| `/rq min` | Collapse/expand the window (also the +/- button at its top-left) |
| `/rq tab <ready\|active\|zone\|zoneprog\|all>` | Switch tab (also `prontas`, `andamento`, `zona`, `todas`) |
| `/rq route` | Plan one journey through every turn-in (Shortest Path Forever) |
| `/rq route here` | Same, only turn-ins on the current map |

- Quests are grouped by turn-in zone. Groups are sorted by **the easiest turn-in**: travel time with Shortest Path Forever, otherwise straight-line distance. A turn-in in the next zone can come before "On this map" when it is closer. Inside each group, quests are sorted the same way.
- **Click**: plan a journey to the turn-in. This uses Shortest Path Forever if installed, otherwise a TomTom waypoint, otherwise it super-tracks the quest.
- **Right-click**: open the quest on the map.
- **Shift-click**: insert the quest link in chat.
- **Route** button (left-click: all quests, right-click: this map only): one journey with nearest-first stops. Quests turned in at the same spot become one stop.
- Drag to move. Drag the bottom-right corner to resize: the width is kept, and the height becomes the maximum. The window shrinks to fit the list, and the mouse wheel scrolls when the list is longer. `/rq lock` hides the grip.

## Tabs
- **Ready**: quests ready to turn in, easiest turn-in first (distance, travel time, rewards).
- **Active**: quests in progress with their objectives (`Wolves slain: 4/8`), nearest first.
- **Zone**: only the quests of the zone you are in, ready ones first.
- **Progress**: how many of your current zone's quests you have done (`12/100`), with the available ones (click to go to the quest giver). Needs Questie.
- **All**: your whole log, grouped by zone.

Click a group header to collapse it. Right-click a quest for a menu (go there, map, track, share, abandon). The window can replace Questie's tracker: see the Tracker options.

## Options
Options > AddOns > **Milkshakson > Ready Quests**, or `/mrq config` (also `/rq config`), or right-click the addon button next to the minimap. From there you can:
- Show, auto-hide and lock the window, and set its width and maximum height.
- Toggle the rewards, dungeon/cave and chain indicators.
- Start a route.
- Pick the language.

## Turn-in place and chains
| Tag | Meaning |
|---|---|
| `Dungeon` (orange) | The turn-in spot is inside an instance |
| `Cave` (tan) | The turn-in spot is inside a cave or a building interior |
| `Chain 2/4` (yellow) | The quest is step 2 of a 4-step chain; the tooltip names the next quest |

The place comes from the map at the turn-in spot. Chains come from the game's quest lines, or from Questie's database (`nextQuestInChain` / `preQuestSingle`) when Questie is installed.

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
