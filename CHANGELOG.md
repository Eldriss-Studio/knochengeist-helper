# Changelog

The helper's versions, newest first. The version is the one in `addons/kg_helper/plugin.cfg`.

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
