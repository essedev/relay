import Foundation

/// Le sezioni della guida su tastiera, aspetto e manutenzione. La tabella delle scorciatoie non è
/// scritta qui: la genera `.allShortcuts` da `ShortcutAction`, così una nuova azione compare da
/// sola in entrambe le rese. Contenuto, non logica (vedi `Guide.swift`).
extension Guide {
    // MARK: - Keyboard

    static var keyboardSection: GuideSection {
        GuideSection(
            id: "keyboard",
            title: "Keyboard",
            symbol: "keyboard",
            summary: "Every shortcut, and how to make them yours.",
            blocks: [
                .paragraph(
                    "Two axes, always the same: workspaces with Command, tabs with Option. "
                        + "Everything else is remappable in Settings > Shortcuts - click a "
                        + "combination, press the new one, conflicts are flagged as you go."
                ),
                .shortcuts([
                    .fixed(keys: "\u{2318}1\u{2013}9", title: "Select workspace",
                           detail: "Follows the sidebar order, pinned rows first."),
                    .fixed(keys: "\u{2325}1\u{2013}9", title: "Select tab",
                           detail: "Within the focused pane."),
                    .fixed(keys: "\u{2325} text", title: "Type layout symbols",
                           detail: "On international layouts Option doubles as AltGr. When it "
                               + "composes a printable character it goes to the terminal instead "
                               + "of triggering a shortcut."),
                ]),
                .allShortcuts,
                .note(
                    "The window moves by dragging the strip at the top, not the terminal below "
                        + "it; double-clicking the strip zooms, like a native title bar."
                ),
            ]
        )
    }

    // MARK: - Appearance & terminal

    static var appearanceSection: GuideSection {
        GuideSection(
            id: "appearance",
            title: "Appearance & terminal",
            symbol: "paintpalette",
            summary: "Themes, fonts, and what the terminal does for you.",
            blocks: [
                .paragraph(
                    "Twelve themes in six dark and light pairs - Relay, Solarized, Gruvbox, "
                        + "Tokyo Night, Catppuccin and GitHub. A theme is a full ANSI palette, so "
                        + "Claude Code, git and ls are painted by it too, and the app's own "
                        + "chrome follows the same colors: badges, rings and group cards are "
                        + "tinted from the palette rather than from a fixed set."
                ),
                .topics([
                    GuideTopic("textformat", "Font",
                               "Any monospace font installed on your Mac, at any size, with an "
                                   + "optional blinking cursor. Zoom in and out per terminal from "
                                   + "the keyboard; the theme's size stays the baseline."),
                    GuideTopic("text.magnifyingglass", "Find in the terminal",
                               "Search the visible screen and the scrollback, with matches "
                                   + "highlighted and next/previous to walk them."),
                    GuideTopic("textformat.size", "The title bar tells you where you are",
                               "It shows what the program set - Claude Code sends the chat name, "
                                   + "zsh sends user@host:path - and falls back to the current "
                                   + "directory, then the workspace folder."),
                    GuideTopic("selection.pin.in.out", "Selection survives output",
                               "Text stays selected while the screen underneath keeps "
                                   + "streaming, so copying from a running build works."),
                ]),
                .note(
                    "Scrollback is capped on purpose, and terminals you have not looked at in a "
                        + "long time are unloaded to keep memory flat in a window full of "
                        + "sessions. Their state, badges and dashboard cards stay."
                ),
            ]
        )
    }

    // MARK: - Housekeeping

    static var housekeepingSection: GuideSection {
        GuideSection(
            id: "housekeeping",
            title: "Updates & upkeep",
            symbol: "gearshape",
            summary: "Staying current, and where Relay keeps its things.",
            blocks: [
                .topics([
                    GuideTopic("arrow.down.circle", "Updates",
                               "Relay checks for a new release at launch and tells you in a "
                                   + "banner; you can skip a version and it will stay quiet until "
                                   + "a newer one appears. Check for Updates in the Relay menu "
                                   + "asks right away, and the check can be turned off."),
                    GuideTopic("chart.bar", "Runtime Stats",
                               "View > Runtime Stats shows memory, CPU, how many workspaces and "
                                   + "tabs are open and how many terminals are actually loaded. "
                                   + "It samples only while the panel is open."),
                    GuideTopic("questionmark.circle", "Welcome and this guide",
                               "Both live in the Help menu. The welcome tour is the short "
                                   + "version, this guide is the long one."),
                    GuideTopic("folder", "Where things are kept",
                               "The layout - windows, workspaces, panes, tabs - is saved as you "
                                   + "work and restored at launch. Preferences live in the "
                                   + "standard macOS defaults, the naming API key in a file only "
                                   + "you can read."),
                ]),
                .paragraph(
                    "To see how the badges behave without running real sessions, Relay can play "
                        + "them for you. Both commands send real events over the same socket the "
                        + "hooks use, so nothing about the path is faked:"
                ),
                .command(
                    "relay-cli simulate",
                    note: "Run it inside a Relay tab: it acts out a fake chat. Add permission for "
                        + "a session that keeps waiting for input, or burst for a stress test."
                ),
                .command(
                    "relay --demo 5x4",
                    note: "Opens five workspaces of four tabs with concurrent simulated "
                        + "sessions, to see a full app at a glance."
                ),
                .note(
                    "Only one Relay runs at a time: launching a second one brings the first "
                        + "forward instead of opening a rival window over the same saved layout."
                ),
            ]
        )
    }

    /// Le poche azioni la cui label da sola non basta. Le altre righe della tabella restano senza
    /// commento: `New Tab` non ha bisogno di una glossa.
    public static let shortcutNotes: [ShortcutAction: String] = [
        .nextAttention: "Jumps to the next session waiting for you, anywhere in the app",
        .prevAttention: "The same, backwards",
        .toggleDashboard: "Every session sorted by urgency",
        .closeTab: "The selected tab of the focused pane",
        .closePane: "Closes the pane with all its tabs",
        .closeWorkspace: "Asks first if something is running",
        .newTab: "Inherits the directory you are working in",
        .toggleGroup: "Groups the selected workspace in a new card, or ungroups it",
        .clear: "Screen and scrollback",
        .actualSize: "Back to the theme's font size",
    ]
}
