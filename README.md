# The Knochengeist helper for Godot

A ghost in the Godot editor's toolbar that answers your questions about Godot. Press Option+G (Alt+G off a Mac), ask anything, and it answers in plain words. When clicks are needed, Show me points at each one on your screen, in order, until it's done.

It answers through your own Claude Code, so it needs no account or key of its own.

## What you need

- **Godot 4.6 or newer.** It's built and tested on 4.7.
- **A Mac**, for now. Windows and Linux are planned.
- **Claude Code** is the only AI it uses for now. Codex (ChatGPT plans) is next, then other popular AI tools.
- **Claude Code**, installed and signed in with your Claude plan. Install it from [claude.com/claude-code](https://claude.com/claude-code), then open Terminal, type `claude` and sign in once.

Each question is one Claude Code run, so it counts toward your plan's usage like any other. If you sign Claude Code in with an API key instead of a plan, each question is billed to that key.

## Install

1. Copy the `addons/kg_helper` folder into your project's `addons` folder (make `addons` if your project has none).
2. In Godot, open Project > Project Settings > Plugins and turn on **Knochengeist helper**.

The ghost appears in the toolbar. It checks that Claude Code is installed and signed in, without making Godot wait.

## Asking

- Press **Option+G**, or click the ghost and pick **Ask the ghost**. Type your question and press Enter.
- The answer appears as it's written. If it involves clicks, **Show me** appears: press it and the ghost points at the first thing to click, then the next, until it's done. Press Esc to stop it pointing.
- **Right-click to ask about something:** in the Scene dock, the FileSystem dock, the Inspector or the script editor, choose **Ask the ghost about this**. The card opens with a question about what you picked, ready to send or change. In the script editor, it asks about the lines you selected.
- The first time you ask in a project, a window says exactly what the helper sends and asks you to allow it (see [What it sends](#what-it-sends)).

## The ghost's menu

Click the ghost, or open Project > Tools > Knochengeist. The first lines say where answers come from right now: your Claude plan (or that questions are billed to your API key), how much of its limit is used and when it resets, and where your Claude Code is. Under them:

- **Ask the ghost**, with its keys. The keys are a Godot editor shortcut: change them in Editor Settings > Shortcuts, under `knochengeist`, and the menu names whatever you picked.
- **Settings…**: your AI (the plan, whether you're signed in, and how much of its limit is used), which Claude Code to run, if it isn't in a usual place, and which model to ask (Sonnet, Fable, Opus or Haiku; Fable and Opus use up your plan's limit faster), and Reduce motion, which makes the ghost appear where it points instead of flying there. They're saved in Editor Settings under `knochengeist/`, so they show there too.
- **Show log**: the helper's log, one line for each check and each question that went wrong, with Claude Code's own words. It's kept small, in the project's user data folder.
- **Copy debug info…**: shows, then copies, what someone needs to look into a problem: the helper and Godot versions, your system, which Claude Code and its version, and how it's signed in. Never a token.
- **About Knochengeist**: the helper's version, with a link to what it sends.

## What it sends

Before it runs Claude Code for the first time in a project, the helper asks, with this text:

> To answer, Knochengeist runs your Claude Code on this computer.
>
> Each question sends to Anthropic, using your account:
> - your question
> - the open scene's file name and the selected node
> - the names of what's on your screen in Godot: buttons, nodes in the Scene dock, files and folders in lists, Inspector properties and hints in text boxes
> - during a walk-through, what you clicked and typed in the boxes it pointed at
> - when you ask about something you right-clicked: its name, or the code you selected
>
> It never sends passwords, stores no logins, and sends nothing else.

Your answer is kept for that project, outside its folder, and it asks again if a different Claude Code would run.

- It runs your own, unmodified `claude`, signed in by you. It never reads, stores or sends your login.
- It starts it with your personal Claude settings, plugins and MCP servers left out (`--setting-sources "" --strict-mcp-config`) and its tools turned off, so it can only answer: it can't change your project or run commands.
- It stops it when you close the card or Godot.
- The helper itself sends nothing anywhere else, and collects no usage data.

## When something's wrong

The ghost is dimmed when it can't answer, and the first line of its menu says why, with the fix:

| The menu says | What to do |
|---|---|
| Claude Code not found | **Install Claude Code…** opens its page. Install it, then come back to Godot: it checks again. |
| Not signed in to Claude Code | **Sign in to Claude Code…** opens Terminal running `claude`. Sign in there, then come back to Godot. |
| No Claude Code at the path in Settings | Open **Settings…** and use Change… to pick `claude`, or Find automatically. |

On the card:

- **"You've used all of your Claude plan's weekly limit. It resets in…"**: wait until then. The ghost warns you once when you're close.
- **"That didn't work"**: press Ask again. If it keeps happening, open **Show log** to see what Claude Code said, and use **Copy debug info…** when you report it.

## Turning it off

Turn it off in Project > Project Settings > Plugins. That removes its shortcut, its log and the files it kept in the project's user data, and forgets that you allowed it to run Claude Code here. Your Claude Code path and model stay in Editor Settings, under `knochengeist/`, in case you turn it on again. To remove it completely, also delete the `addons/kg_helper` folder.

## With the Knochengeist course

If you're taking a Knochengeist course and its course page is running on this computer, the helper answers through the course page instead. That adds your lesson and progress, and the course page's "Show me in Godot". Without the course page, it works on its own as described above.

## Versions

| Helper version | Godot |
|---|---|
| 28 | 4.6 and newer (tested on 4.7) |
| 27 | 4.6 and newer (tested on 4.7) |
| 26 | 4.6 and newer (tested on 4.7) |
| 25 | 4.6 and newer (tested on 4.7) |
| 24 | 4.6 and newer (tested on 4.7) |

What changed in each version is in [CHANGELOG.md](CHANGELOG.md). The helper is MIT licensed ([LICENSE](LICENSE)).

## For developers

The helper is plain GDScript in `addons/kg_helper/`, with the prompts it asks with in `addons/kg_helper/prompts/`. It's built and tested alongside the Knochengeist course, whose tests run it in real headless Godot against stand-ins for Claude Code and for the person using it. Report problems in this repo's [Issues](https://github.com/Eldriss-Studio/knochengeist-helper/issues), with what **Copy debug info…** shows.
