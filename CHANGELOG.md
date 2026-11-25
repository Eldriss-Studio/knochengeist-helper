# Changelog

The helper's versions, newest first. The version is the one in `addons/kg_helper/plugin.cfg`.

## Version 60

- **You pick where answers come from in one list.** In Settings, a single list, **AI**, replaces the two lists. Its items sit under group headings: Your plan (Claude Code (Claude plan), Codex (ChatGPT plan), Copilot (GitHub Copilot plan)), Online, with a key (OpenRouter, DeepSeek), On this computer (Ollama (on this computer), LM Studio (on this computer)) and Somewhere else (Another address). Under OpenRouter, DeepSeek, Ollama, LM Studio and Another address, a quiet line says: "This runs through Claude Code on this computer. You don't need a Claude plan." For those, the Model list now offers models instead of a plain box: OpenRouter's free models, read from OpenRouter's public model list, with the tested default, baidu/ernie-5.5-flash-preview:free, first; the models Ollama has downloaded; the models LM Studio serves; and DeepSeek's deepseek-flash and deepseek-v4-pro. The last item, **Another model…**, shows a box to type any model name. While the list loads it says "Looking for models…". If Ollama or LM Studio doesn't answer, it says: "<Ollama> isn't answering at <address>. Make sure it's running, then open Settings again." The choice you saved in version 59 still works: if you picked OpenRouter, you see OpenRouter in the list, and your key still works. The ghost's menu and its tooltip say "Using OpenRouter" (or the other service's name) when that is your pick, and "Using Claude Code" otherwise. The message for Another address with no address now says to type it under Another address. Before, Settings had two lists: **AI tool**, then **Answers from**, which showed only with Claude Code, and OpenRouter was not a choice of its own.

## Version 59

- **You can use the helper without a Claude plan.** In Settings, with Claude Code picked as the AI tool, a new list, **Answers from**, picks where Claude Code sends its questions: Claude (your Claude plan, the default), OpenRouter, DeepSeek, Ollama (on this computer), LM Studio (on this computer) or Another address. You still need Claude Code installed, but no Claude plan or Claude sign-in. OpenRouter and DeepSeek need a key: paste it into the Key box. It is kept in your computer's own keychain (macOS Keychain, Windows Credential Manager or Linux Secret Service), never in Godot's settings, the log or a file. The box never shows a saved key. It says a key is saved, and **Remove key** removes it. Another address takes an address and an optional key. With a source other than Claude, the Model list becomes a Model box that takes any model name. It starts with baidu/ernie-5.5-flash-preview:free for OpenRouter (a free model), deepseek-flash for DeepSeek, qwen3-coder:30b for Ollama and qwen/qwen3-coder-30b for LM Studio. Effort still applies. Ollama and LM Studio show a note that a good model needs about 16 to 24 GB of graphics memory. A model on your computer answers Godot questions, but it is weaker than Claude at the click walks. The window that asks before your first question in a project now says where questions go. For OpenRouter: "Each question goes to OpenRouter, with your key, and on to the model's maker, Baidu." For Ollama or LM Studio: "Each question stays on this computer: Ollama answers it." For another address: "Each question goes to <its host>." Changing where answers come from asks again. Picking Claude again keeps the consent you already gave Claude Code. When a source refuses, the card now says why: no key saved, no address typed, a wrong key, no credit left, a busy model, an unknown model, or nothing running at the address. Each message names the service and says what to do. Copy debug info has a new "Answers from:" line with the source's name, address and model, never the key. The helper also notes in each answer's record, on your machine, where the answer came from. Before, Claude Code always answered from your Claude plan. A wrong key read as "not signed in", and the other refusals read as "That didn't work".

## Version 58

- **Show me now leads you to things that aren't on screen yet.** For a step in one of Godot's menus, like Scene > New Scene, the ghost rings the menu ("First: Open the Scene menu."). You open it, then the ghost lights up the item and rings the open menu. Picking the item does the step, by click or Enter. This works in Godot's own menu bar (Windows and Linux). On a Mac, Godot's menus are in the Mac's menu bar at the top of the screen, outside Godot's window, where the ghost can't draw. There it says "Choose Scene > New Scene in the menu bar at the top of the screen." and goes on once you pick the item. For a step on a tab that isn't open, like the Output tab at the bottom or Signals next to the Inspector, the ghost rings the tab first, then the thing once it shows. For a step in a folded Inspector section, like Position in Transform, the ghost rings the section's header first, then the property. A section or property below the Inspector's visible part is scrolled into view before it is rung. You always open the menu, tab or section yourself, and the helper never opens them. When a planned step's thing can't be found anywhere, the ghost now says "I can't find <name> on your screen. I'll look for another way." while it asks the AI for another way. The helper counts steps it led you to through a menu, tab or section, on your machine, next to the answer's thumbs. Before, a step whose thing wasn't on screen never matched. After a few seconds the walk dropped its plan and asked the AI for the next click, and it asked silently.

## Version 57

- **The ghost now works with only a keyboard or a screen reader.** The ghost button in the editor's top bar takes keyboard focus and has a name a screen reader reads, "Knochengeist menu". Enter or Space opens its menu, and the arrows and Enter pick from it. Godot's own Tab never goes into the editor's top bar, but Shift+Tab does: from the Scene dock, Shift+Tab reaches the ghost. The Ask shortcut still opens the card directly. On the ask card and the answer card, every button, the question box and the answer text take focus. Tab and Shift+Tab go round them in the order they show on screen and never leave the card. On the answer card the order is the answer, Show me, Close, Yes, No, then the follow-up box. Esc closes the card, and the keyboard goes back to where it was before the card opened. Every control has a name a screen reader reads, such as "Yes, this helped" and "No, this didn't help" on the rating buttons. Settings' three lists are named AI tool, Model and Effort. A screen reader stays quiet while an answer streams in, where the answer is named "Answer still coming", then reads the whole answer once when it is done. Each walk step's text is read as it shows. In a Show me walk, the keyboard moves onto what the ghost rings. Enter or Space presses it the normal way, and the walk counts that as the click. For a row in a list, like a node in Create New Node, the row is picked and Enter does that step only, so it doesn't make the node before the walk's own Create step. Typing in a ringed text box works as before, and Esc still ends a walk. The helper counts walk steps done with a key, on your machine, next to the answer's thumbs. Before, the ghost button couldn't take focus and had no name, the cards' buttons couldn't be reached with Tab, and the answer text wasn't set to be announced, so a screen reader didn't read it unless the person moved to it, and nothing could reach it with Tab. A walk could only be followed with the mouse.

## Version 56

- **You can now select and copy the ghost's answers.** Drag to select text, press Cmd+C (Ctrl+C outside a Mac), or right-click for a small menu with "Copy" and "Select all". Right-click Copy copies your selection, or the whole answer if nothing is selected. Code blocks now show apart from the text, on a light shade in the editor's code font, with a "Copy" link above each one that copies just that code. Web links in an answer now open in your browser, and bold text now shows bold. A long answer no longer pushes the card off the bottom of the screen: the answer scrolls inside the card, and the follow-up box and buttons stay in view. Before, an answer's text couldn't be selected, copied or clicked, and code blocks showed up as plain lines between three backticks.

## Version 55

- **The ghost can now be stopped while it works.** While the ghost thinks or writes an answer, the card now shows a Stop button. Before, the card showed no way out while it worked. Close was hidden, and the only way out was Esc, which closed the card and lost your question. Stop ends the question, both when the AI tool runs on this computer and when the course page answers. The card goes back to the question box with your question still in it, so you can fix it or ask again. Nothing from the stopped answer shows up later. Esc still closes the card.

## Version 54

- **Walk-throughs no longer wait between clicks.** Two cases made the ghost wait. After Show me in Godot on the course page, the ghost asked the AI what comes next after every click. Each wait took about 5 to 7 seconds. Now the page's answer plans every click up front, as asking inside Godot already did, so each next click shows at once. When a walk meets a screen its plan didn't expect, the ghost asked one click at a time for the rest of the walk. Now one question brings every click left, and the rest needs no more questions.

## Version 53

- **Settings fits a laptop screen.** The window was about 1,000 px tall, so on a laptop the Save button fell off the screen. Now it is about 350 to 530 px tall. Each explanation moved into the tooltip of its choice, shown when you hover. Model and Effort sit side by side. "Reduce motion" and "Check for updates" share one line under a new "Options" heading. The window shrinks when a tool has fewer choices, such as Copilot. The Godot docs line wraps instead of widening the window.

## Version 52

- **No more stutter while the course page is running.** The editor used to hitch once a second, because each look at the screen took about 36 ms. A look now takes under half a millisecond.

## Version 51

- **Works on Godot 4.6.** Versions 28 to 50 did not load at all on 4.6. They used the Inspector's right-click spot, which only exists from Godot 4.7. Version 51 loads on 4.6 and leaves that one spot out. Right-click in the Scene dock, the FileSystem dock and the script editor works there as before. On 4.7 all four spots work. Each release is now checked to load with no errors or warnings on 4.7 and 4.6.

## Version 50

- **Walk-throughs work in single-window mode.** With Godot set to draw its dialogs inside the editor window, clicking what the ghost pointed at in a dialog (Create New Node, for one) wasn't noticed, so the walk-through stalled there. Now it goes on to the next step.
- **Settings fully in your language.** The "Getting the manual for Godot…" line was still in English. Now it follows the editor's language like the rest.

## Version 49

- **Answers come sooner, and you choose how hard the AI thinks.** Settings has a new **Effort** choice for Claude Code and Codex: Low (the default), Medium or High. At Low, Claude Code's whole answer with Show me is ready in about 4.3 seconds instead of 5.8 (median of ten real runs), and the answer evals pass the same. Pick High when you'd rather it think longer. Copilot decides this itself, so it has no choice to make.
- **Fully in your language, whichever AI tool you use.** The ghost's card, the walk-through labels and right-click questions are now translated too. The Allow screen names the tool you picked and its company, instead of always Claude Code and Anthropic.

## Version 48

- **In your editor's language.** The menu, the ghost's cards, Settings and every message now follow the language you set for the Godot editor: Brazilian Portuguese and Spanish to start, English otherwise. The ghost already answered in your language; now everything around it does too. Your game's own translations aren't touched.

## Version 47

- **Install from the helper.** "Install Claude Code…", "Install Codex…" and "Install Copilot…" in the ghost's menu, and Install… in Settings, run that tool's own installer in a terminal you can watch. None of them needs Node. Back in Godot, the helper looks for it again.
- **Clearer Settings.** Plainer words throughout: "Choose file…" instead of "Change…", what to do when something's missing, and the dropdown names the plan each tool runs on.

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
