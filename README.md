# Kubiya · קובייה

![Kubiya screenshot](docs/screenshot.png)
![Mining and building with touch controls](docs/screenshot-touch.png)

**English** | [עברית](#עברית)

Kubiya is an original, open-source 3D block sandbox game built with Godot 4 and GDScript.
One codebase targets macOS, Windows, Android, iOS and the web browser.

Kubiya is not affiliated with Mojang or Microsoft and is not a copy of any existing game.
The name, textures, sounds and music are original. Textures are generated in code.

## Status

Early development. Stages 1 to 3 are done: an endless generated world with hills,
sea, caves, trees and ores; mining and building; keyboard, mouse and touch controls;
sound effects and background music generated in code.

| Stage | Content | State |
|-------|---------|-------|
| 1 | Repository, project skeleton, terrain, walking | Done |
| 2 | Endless world: 16x16x128 chunks, hills, water, caves, trees, ores, streaming | Done |
| 3 | First-person player, mining, building, hotbar, touch controls, sounds, music | Done |
| 4 | Inventory, crafting, save and load | Planned |
| 5 | Day and night, lighting, monsters, health, menus | Planned |
| 6 | Builds: macOS `.dmg`, Windows, Android APK, iOS, web | Planned |
| 7 | Download site on GitHub Pages with the browser version | Planned |

## Controls

| Action | Key |
|--------|-----|
| Move | W A S D or arrow keys |
| Look | Mouse (click the window first) |
| Jump / swim up | Space |
| Run | Shift |
| Mine | Hold left mouse button |
| Place block | Right mouse button |
| Choose block | 1 to 9, or mouse wheel |
| Music on / off | M |
| Release mouse | Esc |

Touch: joystick on the left, buttons for jump, mine (hold) and place on the right,
drag anywhere else to look, tap a hotbar slot to choose a block.

## Run from source

Ready-made downloads arrive in stage 6. Until then:

1. Install [Godot 4.7](https://godotengine.org/download) or newer.
2. Clone this repository.
3. Open `project.godot` in Godot and press F5.

## License

MIT. See [LICENSE](LICENSE).

---

<div dir="rtl">

## עברית

קובייה (Kubiya) הוא משחק בלוקים תלת־ממדי מקורי בקוד פתוח, בנוי ב־Godot 4 וב־GDScript.
קוד אחד מיועד למק, ווינדוס, אנדרואיד, אייפון ודפדפן.

המשחק אינו קשור ל־Mojang או ל־Microsoft ואינו העתק של משחק קיים.
השם, הטקסטורות, הצלילים והמוזיקה מקוריים. הטקסטורות נוצרות בקוד.

### מצב

פיתוח מוקדם. שלבים 1 עד 3 הושלמו: עולם אינסופי עם גבעות, ים, מערות, עצים ועפרות; כרייה ובנייה; שליטה במקלדת, עכבר ומגע; צלילים ומוזיקת רקע שנוצרים בקוד.

| שלב | תוכן | מצב |
|-----|------|-----|
| 1 | ריפו, שלד הפרויקט, עולם, הליכה | בוצע |
| 2 | עולם אינסופי: צ'אנקים 16x16x128, גבעות, מים, מערות, עצים, עפרות, טעינה דינמית | בוצע |
| 3 | שחקן בגוף ראשון, כרייה, בנייה, סרגל חפצים, שליטה במגע, צלילים, מוזיקה | בוצע |
| 4 | מלאי, יצירת חפצים, שמירה וטעינה | מתוכנן |
| 5 | יום ולילה, תאורה, מפלצות, חיים, תפריטים | מתוכנן |
| 6 | גרסאות: מק (`.dmg`), ווינדוס, אנדרואיד (APK), אייפון, דפדפן | מתוכנן |
| 7 | אתר הורדה ב־GitHub Pages עם גרסת הדפדפן | מתוכנן |

### מקשים

| פעולה | מקש |
|-------|-----|
| תנועה | W A S D או מקשי החצים |
| מבט | עכבר (קודם לוחצים על החלון) |
| קפיצה / שחייה למעלה | רווח |
| ריצה | Shift |
| כרייה | לחיצה ארוכה על כפתור שמאלי |
| הצבת בלוק | כפתור ימני |
| בחירת בלוק | 1 עד 9, או גלגלת |
| מוזיקה | M |
| שחרור העכבר | Esc |

מגע: ג'ויסטיק משמאל, כפתורי קפיצה, כרייה (לחיצה ארוכה) והצבה מימין,
גרירה בכל מקום אחר מזיזה את המבט, נגיעה במשבצת בסרגל בוחרת בלוק.

### הרצה מהקוד

הורדות מוכנות יגיעו בשלב 6. עד אז:

1. מתקינים [Godot 4.7](https://godotengine.org/download) ומעלה.
2. משכפלים את הריפו.
3. פותחים את `project.godot` ב־Godot ולוחצים F5.

### רישיון

MIT. ראו [LICENSE](LICENSE).

</div>
