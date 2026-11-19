# Changelog

The helper's versions, newest first. The version is the one in `addons/kg_helper/plugin.cfg`.

## Version 46

- **Settings checks the AI tool you pick right away.** No more "Save to check": pick Codex or Copilot and Settings says at once whether it's there and signed in, and its Sign in button signs in to that tool.
- **Copilot uses the sign-in you already have.** Version 45 asked you to sign in again inside the helper. Now it finds your own `copilot login` through your account name (never your token), while its questions still stay out of your Copilot history and aren't synced to your GitHub account.
- The helper's main file is split into its three jobs (the course app link, reading the screen, and the walk-through), with no change to what it does.

## Version 45

- **Copilot, for GitHub Copilot plans (Free included).** Pick it under **AI tool** in Settings. The helper answers through `copilot` with every tool off and your own instructions and MCP servers ignored, so only your question is sent, to GitHub. It runs Copilot with its own settings folder, so these questions stay out of your Copilot history. Copilot can't be checked for sign-in without spending a request, so your first question finds out, and the menu then offers **Sign in to Copilot…**.
- When any AI tool turns out to be signed out mid-question, the menu now says so and offers Sign in right away.

## Version 44

- **Codex, for ChatGPT plans.** Pick **AI tool** in Settings: Claude Code or Codex. With Codex, the helper answers through `codex exec` with its shell and web search turned off, so only your question is sent, to OpenAI. Show me, follow-ups and the name check work the same. Codex answers all at once, and doesn't report your plan's usage, so the ring stays hidden.
- The helper finds the Codex that comes with the ChatGPT app, so with the app installed and signed in there's nothing else to set up.
- Settings follows the tool you pick before you save: its model, its location, and whether it's signed in ("Signed in to Codex", or Sign in…).

## Version 43

- **Works on Windows.** The helper finds Claude Code (`claude.exe` under your profile, npm's `claude.cmd`, or the PATH), answers, stops when you close the card, and opens a console to sign in. Its tests now run on Windows, Linux and macOS.
- Claude Code now starts the same way on every computer, and empty flags like "no tools" can't swallow the next one anymore.
- A Claude Code that fails without saying it's signed out is shown as one that won't start, so the menu points at the real problem.

## Version 42

- **Works on Linux.** Sign in to Claude Code opens your default terminal (or GNOME Terminal, Konsole or xterm), and the helper's whole test set now runs on Linux too. Windows is next.

## Version 41

- **The ghost shows when your plan is nearly used up.** Past 80% of your Claude plan's limit, the toolbar ghost wears a ring filled to how much is used, red from 95%, and its tooltip says when the limit resets.

## Version 40

- **The ghost reads Godot's manual for your version.** Most questions are how-tos, and the manual answers those, so a question now comes with the matching manual pages for your Godot, with their links. The helper downloads the manual from GitHub once per Godot version and checks it. Settings says when a newer Godot's manual isn't out yet. With the manual, the full answer eval passes 110 of 114 tries.
- The name check no longer mistakes `@GlobalScope` for a made-up name.

## Version 39

- **"Your game hit an error."** When a run of your game prints an error, the ghost offers to explain it, once per run. Click it, or pick **Explain the last error** in its menu, and the card opens with the question ready, the error and the lines of your script around it. Nothing is sent until you press Ask.

## Version 38

- **The ghost checks its Godot names against your Godot.** If an answer names a class or method your Godot doesn't have, like a made-up node or a Godot 3 method, the ghost asks Claude Code again with the real reference pages, and shows the fixed answer. If a name still isn't there, the answer says to check that name.
- **Questions that name something in Godot come with its reference pages,** from your own Godot, so newer features aren't guessed from memory.
- Settings says what Godot docs does: "Ready for Godot 4.7.2", and that the ghost checks its names against it.

## Version 37

- **Answers in your editor's language.** With Godot set to Portuguese, the ghost answers in Portuguese, and Show me's steps are in Portuguese too, naming the buttons as your editor shows them. On the ten "add a node" questions with the editor in Portuguese, 29 of 30 tries pass.
- Show me no longer skips "Create" and makes the wrong node. When a planned click wasn't on screen, it could jump ahead to the next search box, which is the same box as before, and pick the next node instead.

## Version 36

- **Follow-up questions.** After an answer, the box at the bottom of the card takes a follow-up, and the ghost knows what you asked before, so "and how do I make it brighter?" works. Closing the card starts a new conversation.
- **Recent questions** in the ghost's menu lists your last five questions in this project. Picking one shows its answer again, straight away, without asking Claude Code.

## Version 35

- Under each finished answer, a quiet **Did this help? Yes / No**. After No, you can say what was wrong. Your marks stay on your computer, in the project's user data folder. When you report a problem, **Copy debug info…** can include your last five answers that didn't help, shown to you before anything is copied.

## Version 34

- Show me no longer gets stuck on a search box it already had you type in. While it waited for the next click, it counted your typing again every second, until the walk gave up as "a long one". Now each typing counts once, and pointing back at a box that already holds what you typed moves on. On Haiku, the "add a node" walks now pass 28 of 30 tries (from 16).

## Version 33

- Settings reads in the order you'd use it: your account, then the model (each one says what it's for), then the Godot docs and where Claude Code is, then motion and updates. Every hint sits under its control.

## Version 32

- When Show me walks you through adding a node, the answer now also says what you'll set or use on it next, like a Timer's timeout signal or a sound's Stream property. In the answer evals, every "add a node" question now passes all three tries.

## Version 31

- The helper keeps a searchable copy of Godot's class reference, built from your own Godot the first time it starts (about 2 seconds, without making the editor wait), so it always matches your version. Settings says when it's ready. Nothing is downloaded. The ghost starts using it in its answers in the next version.

## Version 30

- Show me no longer skips the step where you type in a search box or pick an item. When the ghost can't find that box under the name it planned, it finds the one that matches, or asks for the next click. Before, it could jump ahead to Create and add the wrong node.

## Version 29

- The helper updates itself from its menu: when a newer version is out, **Update to version…** shows what's new and installs it in one click. It checks GitHub once a day; turn that off in Settings.

## Version 28

- Right-click a node, a file, an Inspector property or selected code and choose **Ask the ghost about this**: the card opens with a question about it, and the question carries what you picked.

## Version 27

- About is short, with a "What it sends" link.
- The card, hello and notes keep clear of the Inspector when there's room.
- The menu shows Ask's keys in its own shortcut column.
- Less motion in Settings: the ghost appears where it points instead of flying, and doesn't bob while it thinks.
- A planned walk-through says which step of how many ("Step 1 of 3").
- Settings shows which Claude Code is used and whether it was found automatically, with Change… and Find automatically, instead of an empty box.
- Every message, menu entry and window was reworded in one plain voice, like Godot's own editor.

## Version 26

From a UI review with real screenshots.

- Fable is a model choice. The menu and Settings say which model answered, and every usage window Claude Code reports.
- A Claude Code that's there but won't start is no longer called ready; the menu says so.
- The menu stays narrow: long Claude Code paths are shortened.
- The Allow window lists what each question sends instead of one long paragraph.
- Settings shows your plan once, a visible usage bar, and has Cancel; the path box shows the path's end.
- A failed question offers Ask again and points to Show logs. The card says Enter asks and Esc closes.

## Version 25

- The ghost's menu and Settings show your Claude plan, whether you're signed in, and how much of its limit is used, with when it resets. With an API key, they say questions are billed to it and what the last one cost.
- At the limit, the card says when it resets. Close to it, the ghost says so once.
- The Settings window fits its content instead of filling the editor's height.

## Version 24

The first version meant for anyone to install.

- Answers your Godot questions through your own Claude Code, with no course page needed, and walks you through the clicks with Show me.
- The ghost's menu (also under Project > Tools > Knochengeist): where answers come from, Ask, Settings, Show logs, Copy debug info, About.
- Checks that Claude Code is installed and signed in when it starts, and shows the fix in the menu.
- Asks once per project before running Claude Code, and says exactly what each question sends. Password fields are never sent.
- Its keys (Option+G, Alt+G off a Mac) are a Godot editor shortcut you can change.
- Plain messages for a used-up plan, a billing problem, a Claude Code that skips your sign-in, or one that answers in a way this version doesn't understand.
- Turning it off removes its shortcut and files; your Claude Code path and model stay.
- Needs Godot 4.6 or newer, and a Mac for now.
