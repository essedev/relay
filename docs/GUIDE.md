# Relay - user guide

Everything Relay can do, in one place. Generated from the app's own guide (`make guide-md`):
edit `Sources/WorkspaceModel/Guide*.swift`, not this file.

Open the same guide inside the app from **Help > Relay Guide**.

## Contents

- [Workspaces & tabs](#workspaces) - One home per project, with as many terminals as it needs.
- [Panes & windows](#panes) - Split the view, and spread workspaces across screens.
- [The sidebar](#sidebar) - Groups, pinning, archive, and everything you can drag.
- [Agent state](#agents) - What your sessions are doing, and what is waiting for you.
- [Home and Projects](#dashboard) - What needs you, and every project you have, open or closed.
- [Automatic naming](#naming) - A workspace takes its name from what is happening in it.
- [Keyboard](#keyboard) - Every shortcut, and how to make them yours.
- [Appearance & terminal](#appearance) - Themes, fonts, and what the terminal does for you.
- [Updates & upkeep](#housekeeping) - Staying current, and where Relay keeps its things.

<a id="workspaces"></a>

## Workspaces & tabs

A workspace is a project: a folder, a name, and the tabs you opened for it. Relay keeps them apart
so that switching context is one keystroke instead of a hunt through a flat list of terminals.

- **Open a folder as a workspace** - The folder becomes the workspace root and the name you see. New
  tabs start there.
- **Start without a folder** - A workspace with no root starts in your home directory. Useful for a
  quick shell you do not want to lose track of.
- **New things are born next to you** - A new tab lands right after the selected one in the focused
  pane, and a new workspace right after the selected one, inside its group. Nothing is appended to
  the bottom, where it would be the first thing pushed down by activity.
- **Rename anything** - Right-click a workspace to rename it inline. Tabs take their title from the
  program running in them: Claude Code sends the chat name, zsh sends user@host:path.
- **Move a tab out** - “Move to New Workspace” in a tab's context menu promotes it to a workspace of
  its own, rooted at its current directory. The terminal keeps running: it is the same session, in a
  new home. Available from two tabs up.

New tabs inherit the directory you are actually working in, read from the live shell rather than
from the last prompt, so a tab opened after a few cd commands starts where you left off.

**Note:** Closing a tab that is running something in the foreground asks first, and names what is
running. Closing a tab stops everything started in it, background jobs too, even under nohup: a job
that has to outlive the tab belongs in tmux or a launchd job. Closing the last tab of a workspace
closes the workspace with it.

<a id="panes"></a>

## Panes & windows

Splitting gives you a second terminal beside the first. The part worth knowing: in Relay a pane is
not a terminal, it is a container that holds tabs. Each pane has its own tab strip and its own
selection, so a quarter of the screen can hold three tabs and you cycle through them without
touching the other panes.

- **Split from the keyboard** - Split right or down divides the focused pane in half. The new pane
  takes the focus and starts with one tab.
- **Split from a tab** - “Open in Split Right” and “Open in Split Down” in a tab's context menu send
  that tab to a new pane instead of opening an empty one. The action lane at the end of each strip
  does the same with the mouse.
- **Focused is not the same as visible** - Every pane shows a tab, but only one pane has the
  keyboard. Shortcuts that act on “the tab” mean the selected tab of the focused pane.
- **Resize and close** - Drag a divider to change the ratio; it is remembered with the layout.
  Closing the last tab of a pane closes the pane and its sibling takes the space.
- **A workspace in its own window** - “Move Workspace to New Window” from the sidebar context menu
  moves it to a window of its own, handy on a second screen. Its sessions keep running through the
  move, and each window has its own sidebar listing only its workspaces.

**Note:** Windows, panes, tabs and the divider ratios come back where you left them after a restart.
Terminals do not: a shell cannot be resurrected, but an agent session can be resumed (see Agent
state).

<a id="sidebar"></a>

## The sidebar

The sidebar is the list of your workspaces, and its order is real: it is the order you put them in,
saved with the layout. Two things move a row - your own drag, and a workspace finishing work while
you were looking elsewhere, which floats to the top of wherever it lives.

- **Groups** - A colored card around related workspaces, from a row's context menu or the Workspace
  menu. Collapsed, the card is as tall as a single row and shows one number: how many members are
  waiting for you. A group with no members stops existing.
- **Pinning** - A pinned row - or a whole pinned group - leads the list. Everything else keeps its
  own order below.
- **Closing a project** - Close a project you are not on right now, from the x on its row or the
  Workspace menu. Nothing is lost: it keeps its group, its tabs and its agent sessions, which you
  can resume when you open it again. Its processes stop, so the memory comes back. Closed projects
  wait in the section at the bottom.

Four things can be dragged, and they are all the same gesture - press a row or a tab and move it:

- **A workspace, to reorder it** - Dragging across the pinned block at the top pins or unpins it.
- **A workspace, in or out of a group card** - Dropping just inside the bottom edge of a card means
  joining it; dropping just below means leaving it. The card has a dedicated last row so the two are
  never the same pixel.
- **A workspace, onto Closed** - Closes the project; drag it back out to open it again. The header
  is always there, even when empty, so the target never moves.
- **A tab, onto another workspace** - Pull a tab out of its strip and drop it on a workspace row: it
  moves there with its terminal still running, and the target is revealed - reopened, its card
  opened. Moving the last tab out closes the workspace it came from.

**Note:** The sidebar does not scroll while you drag a tab onto it, so scroll to the target first.
Tab drops land on workspace rows, not on group headers, and the tab joins the focused pane of the
destination.

<a id="agents"></a>

## Agent state

Relay knows what Claude Code and Codex are doing because their native callbacks (hooks) report when
a session starts working, asks for input, or finishes. Nothing is guessed from the terminal output,
so the badges stay right even when the screen is full of build logs.

1. Install the hooks once, from Settings > Agents or with relay-cli hooks setup all.
2. Run claude or codex in any tab. The tab is bound to that session automatically.
3. The badge on the tab, and the aggregate badge on its workspace, follow along.

```sh
relay-cli hooks status all
```

Check both integrations. Relay appends marked entries to Claude Code and Codex configuration, so
your existing hooks stay in place; relay-cli hooks uninstall all removes only ours. Replace all with
claude or codex to manage one agent; omitting it defaults to claude.

**Note:** A Relay release can add a hook, and a configuration written by an older version would stay
one event short without saying so. Settings and relay-cli hooks status name the missing events, and
Relay puts back the ones Claude Code needs on its own at launch.

**Note:** Use a Codex CLI version with native hook support. In Codex, review user hooks with /hooks
after installation and whenever definitions change. Because that trust has to be renewed, Relay
never rewrites the Codex configuration on its own: if it falls behind, Settings tells you and the
button becomes Update. Installed means the configuration is present; Relay cannot check whether
Codex has trusted it.

Attention is a separate thing from state. A session that finished is not news forever, and Relay
says so in three steps rather than with one badge that stays until you click it:

- **Unseen: it wants you** - A ring around the terminal and a full badge on the tab. Its workspace
  also floats to the top of the sidebar, so you find it without looking.
- **Pending: seen, not picked up** - Typing in a terminal you are looking at demotes its signal to a
  quiet one: no ring, just a hollow badge. It says “you know about this, you have not answered”.
- **Resolved: gone** - Actually replying to the session clears it, and so do /clear and /resume,
  marking it read from the sidebar, and closing the tab. A pending signal also fades on its own
  after twelve hours, which you can change or switch off.

Navigating does not count as reading: switching tabs in a strip or clicking a row in the sidebar
leaves the signal alone. Only working inside the terminal does. When you disagree, the context menu
has Mark as Read and Mark as Unread on the tab.

- **Errors stop the session** - Claude Code reports when a turn dies on an API error - rate limit,
  overloaded, billing, no network - the turn ends without finishing. The tab goes red and calls you
  like any other unseen signal: ring, badge, a float to the top and a notification. Every kind of
  error looks the same here; the terminal has the details. Retrying clears it. Codex currently has
  no equivalent failure hook, so those failures remain visible only in its terminal output.
- **Notifications** - macOS notifications when a session needs input, hits an error, or finishes
  while you are not looking at its tab. Clicking one brings that tab up, wherever it is. Per-type
  toggles and the sound are in Settings.
- **Resume after a restart** - Terminals do not survive a restart, but agent sessions can: a
  restored tab with a session offers a Resume bar that types the resume command for you. Settings
  can make it automatic; the default asks, because nothing should type commands into your shell
  unannounced. Quitting hangs up every session Relay started, and anything still running from a
  previous run, such as an agent stuck past the hangup or a session left behind by a crash, is
  stopped at launch before anything resumes, so a session never runs twice.
- **Deactivate a session** - An agent session costs a couple of hundred megabytes and a handful of
  processes, and Relay never evicts a tab that still has one running. Deactivate Sessions, in the
  Workspace menu or on a sidebar row, stops them and keeps the way back: the tabs stay where they
  are and reopening one offers to resume. Tabs on screen and agents that are working are left alone,
  and the confirmation says so. A deactivated tab never resumes on its own, even with automatic
  resume on: you can open it to look without starting it again.

**Note:** If a resume ends in command not found, something in that tab was waiting for input and
took the first character as its answer: a resume types into the shell exactly as you would, it does
not wait for a prompt. The failed line still carries the whole session id, so you can run the
command by hand. To stop it happening, answer or silence whatever asks at shell startup; for the
oh-my-zsh update prompt that is zstyle ':omz:update' mode auto in ~/.zshrc.

**Note:** Notifications need a bundle identifier, so they work in the installed app, not when
running from a development build.

<a id="dashboard"></a>

## Home and Projects

With a dozen sessions running, the question is not “what is in this tab” but “what should I look at
next”. Home answers that, in place of the terminals: its title says how many sessions need you, and
each one comes with the line the agent left on screen and the action it wants.

- **Needs you** - Waiting for an answer, stopped on an error, or finished and not reviewed. Answer,
  Check or Review takes you to the tab.
- **Working** - Sessions running on their own, one compact row each.
- **Quiet for a week** - Open projects that have not moved in seven days. Closing them frees their
  terminals; their sessions stay resumable.
- **Projects** - The catalog of every project, by group, open or closed. Filter by name or folder; a
  click opens a closed project with its tabs, ready to resume.
- **Go to project** - ⌘P from anywhere: a few letters of the name or the folder, Return to go. Open
  projects come first.

**Note:** Home and Projects sit on top of the terminals without stopping them: Esc, or picking a
project in the sidebar, takes you straight back.

<a id="naming"></a>

## Automatic naming

A workspace opened without a folder is called “Workspace 3”, which tells you nothing when there are
nine of them. Relay renames it after what it is actually doing: the folder you cd into, a command
running in one of its tabs, an agent session and the topic of its chat. With an agent in the tab
Relay waits for the chat to get its title, up to a minute. The name pulses while it is being worked
out.

Out of the box the name is derived from those signals - “yellow-hub” becomes “Yellow Hub”, “npm run
dev” becomes “Npm Dev”. No key, no network, no wait.

1. Open Settings > Agents > Workspace naming for the switch.
2. Optional: paste an API key to have a model write the names instead. The default endpoint is
   OpenRouter; any OpenAI-compatible base URL and model work.
3. “Regenerate name” in a workspace's context menu asks for another one right away. Without a key
   the names are derived by rule, so there is often only one to give.

A name you typed yourself is never overwritten: renaming a workspace by hand opts it out for good. A
placeholder or a folder name is fair game, and once named the workspace is left alone.

**Note:** The key is stored in a file only you can read, not in the preferences plist. A name is a
couple of hundred tokens on a cheap default model, but it is your account - and the derived names
cost nothing, so the key is an upgrade, not a requirement. The model sees the folder's name (not its
path), the running command and the agent chat's title, nothing else.

<a id="keyboard"></a>

## Keyboard

Two axes, always the same: workspaces with Command, tabs with Option. Everything else is remappable
in Settings > Shortcuts - click a combination, press the new one, conflicts are flagged as you go.
Fixed and not remappable: those two number axes, the terminal control keys, and the macOS menu
commands, this guide's own ⌘? included.

| Keys | Action | Notes |
| --- | --- | --- |
| `⌘1–9` | Select workspace | Follows the sidebar order, pinned rows first. |
| `⌥1–9` | Select tab | Within the focused pane. |
| `⌥ text` | Type layout symbols | On international layouts Option doubles as AltGr. When it composes a printable character it goes to the terminal instead of triggering a shortcut. |

### Workspace

| Keys | Action | Notes |
| --- | --- | --- |
| `⌘N` | New Workspace |  |
| `⌘O` | Open Folder as Workspace… |  |
| `⌥⇧⌘W` | Close Workspace | Asks first if something is running |
| `⌃⌘G` | Group / Ungroup Workspace | Groups the selected workspace in a new card, or ungroups it |
| `⇧⌘P` | Projects | Every project, open or closed, by group |
| `⌘P` | Go to Project… | Type a few letters of any project; a closed one reopens |
| `⌥⌘↓` | Next Workspace |  |
| `⌥⌘↑` | Previous Workspace |  |

### Window

| Keys | Action | Notes |
| --- | --- | --- |
| `⇧⌘N` | New Window |  |
| `⇧⌘W` | Close Window |  |

### Tab

| Keys | Action | Notes |
| --- | --- | --- |
| `⌘T` | New Tab | Inherits the directory you are working in |
| `⌘W` | Close Tab | The selected tab of the focused pane |
| `⌃⇥` | Next Tab |  |
| `⌃⇧⇥` | Previous Tab |  |

### Pane

| Keys | Action | Notes |
| --- | --- | --- |
| `⌘\` | Split Right |  |
| `⇧⌘\` | Split Down |  |
| `⌥⌘W` | Close Pane | Closes the pane with all its tabs |
| `⌘]` | Next Pane |  |
| `⌘[` | Previous Pane |  |

### Agent

| Keys | Action | Notes |
| --- | --- | --- |
| `⌘J` | Next Attention | Jumps to the next session waiting for you, anywhere in the app |
| `⇧⌘J` | Previous Attention | The same, backwards |
| `⌘D` | Home | What needs you, and what to put away |

### Terminal

| Keys | Action | Notes |
| --- | --- | --- |
| `⌘F` | Find… |  |
| `⌘G` | Find Next |  |
| `⇧⌘G` | Find Previous |  |
| `⌘K` | Clear Terminal | Screen and scrollback |

### View

| Keys | Action | Notes |
| --- | --- | --- |
| `⌘B` | Toggle Sidebar |  |
| `⌘+` | Make Text Bigger |  |
| `⌘-` | Make Text Smaller |  |
| `⌘0` | Actual Size | Back to the theme's font size |

**Note:** The window moves by dragging the strip at the top, not the terminal below it;
double-clicking the strip zooms, like a native title bar.

<a id="appearance"></a>

## Appearance & terminal

Twelve themes in six dark and light pairs - Relay, Solarized, Gruvbox, Tokyo Night, Catppuccin and
GitHub. A theme is a full ANSI palette, so Claude Code, git and ls are painted by it too, and the
app's own chrome follows the same colors: badges, rings and group cards are tinted from the palette
rather than from a fixed set.

- **Font** - Any monospace font installed on your Mac, at any size, with an optional blinking
  cursor. Zoom in and out per terminal from the keyboard; the theme's size stays the baseline.
- **Find in the terminal** - Search the visible screen and the scrollback, with matches highlighted
  and next/previous to walk them.
- **The title bar tells you where you are** - It shows what the program set - Claude Code sends the
  chat name, zsh sends user@host:path - and falls back to the current directory, then the workspace
  folder.
- **Selection survives output** - Text stays selected while the screen underneath keeps streaming,
  so copying from a running build works.

**Note:** Scrollback is capped on purpose, and terminals you have not looked at in a long time are
unloaded to keep memory flat in a window full of sessions. Their state, badges and rows in Home
stay.

<a id="housekeeping"></a>

## Updates & upkeep

- **Updates** - Relay checks for a new release at launch and tells you in a banner; you can skip a
  version and it will stay quiet until a newer one appears. Check for Updates in the Relay menu asks
  right away, and the check can be turned off.
- **Runtime Stats** - View > Runtime Stats shows memory, CPU, how many workspaces and tabs are open
  and how many terminals are actually loaded. It samples only while the panel is open.
- **Welcome and this guide** - Both live in the Help menu. The welcome tour is the short version,
  this guide is the long one.
- **Where things are kept** - The layout - windows, workspaces, panes, tabs - is saved as you work
  and restored at launch. Preferences live in the standard macOS defaults, the naming API key in a
  file only you can read.

To see how the badges behave without running real sessions, Relay can play them for you. Both
commands send real events over the same socket the hooks use, so nothing about the path is faked:

```sh
relay-cli simulate
```

Run it inside a Relay tab: it acts out a fake chat. Add permission for a session that keeps waiting
for input, or burst for a stress test.

```sh
relay --demo 5x4
```

Opens five workspaces of four tabs with concurrent simulated sessions, to see a full app at a
glance.

**Note:** Only one Relay runs at a time: launching a second one brings the first forward instead of
opening a rival window over the same saved layout.
