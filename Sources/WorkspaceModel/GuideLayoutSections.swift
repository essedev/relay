import Foundation

/// Le sezioni della guida che descrivono il contenitore: workspace e tab, pane e finestre, sidebar.
/// Contenuto, non logica (vedi `Guide.swift` per il formato e le regole di scrittura).
extension Guide {
    // MARK: - Workspaces & tabs

    static var workspacesSection: GuideSection {
        GuideSection(
            id: "workspaces",
            title: "Workspaces & tabs",
            symbol: "square.grid.2x2",
            summary: "One home per project, with as many terminals as it needs.",
            blocks: [
                .paragraph(
                    "A workspace is a project: a folder, a name, and the tabs you opened for it. "
                        + "Relay keeps them apart so that switching context is one keystroke "
                        + "instead of a hunt through a flat list of terminals."
                ),
                .topics([
                    GuideTopic("folder.badge.plus", "Open a folder as a workspace",
                               "The folder becomes the workspace root and the name you see. New "
                                   + "tabs start there."),
                    GuideTopic("plus.square", "Start without a folder",
                               "A workspace with no root starts in your home directory. Useful "
                                   + "for a quick shell you do not want to lose track of."),
                    GuideTopic("arrow.down.right.square", "New things are born next to you",
                               "A new tab lands right after the selected one in the focused pane, "
                                   + "and a new workspace right after the selected one, inside "
                                   + "its group. Nothing is appended to the bottom, where it "
                                   + "would be the first thing pushed down by activity."),
                    GuideTopic("character.cursor.ibeam", "Rename anything",
                               "Right-click a workspace to rename it inline. Tabs take their "
                                   + "title from the program running in them: Claude Code sends "
                                   + "the chat name, zsh sends user@host:path."),
                    GuideTopic("arrow.up.forward.square", "Move a tab out",
                               "\u{201C}Move to New Workspace\u{201D} in a tab's context menu "
                                   + "promotes it to a workspace of its own, rooted at its "
                                   + "current directory. The terminal keeps running: it is the "
                                   + "same session, in a new home. Available from two tabs up."),
                ]),
                .paragraph(
                    "New tabs inherit the directory you are actually working in, read from the "
                        + "live shell rather than from the last prompt, so a tab opened after a "
                        + "few cd commands starts where you left off."
                ),
                .note(
                    "Closing a tab that is running something in the foreground asks first, and "
                        + "names what is running. Closing the last tab of a workspace closes the "
                        + "workspace with it."
                ),
            ]
        )
    }

    // MARK: - Panes & windows

    static var panesAndWindowsSection: GuideSection {
        GuideSection(
            id: "panes",
            title: "Panes & windows",
            symbol: "square.split.2x1",
            summary: "Split the view, and spread workspaces across screens.",
            blocks: [
                .paragraph(
                    "Splitting gives you a second terminal beside the first. The part worth "
                        + "knowing: in Relay a pane is not a terminal, it is a container that "
                        + "holds tabs. Each pane has its own tab strip and its own selection, so "
                        + "a quarter of the screen can hold three tabs and you cycle through "
                        + "them without touching the other panes."
                ),
                .topics([
                    GuideTopic("square.split.2x1", "Split from the keyboard",
                               "Split right or down divides the focused pane in half. The new "
                                   + "pane takes the focus and starts with one tab."),
                    GuideTopic("rectangle.stack.badge.plus", "Split from a tab",
                               "\u{201C}Open in Split Right\u{201D} and \u{201C}Open in Split "
                                   + "Down\u{201D} in a tab's context menu send that tab to a new "
                                   + "pane instead of opening an empty one. The action lane at "
                                   + "the end of each strip does the same with the mouse."),
                    GuideTopic("viewfinder", "Focused is not the same as visible",
                               "Every pane shows a tab, but only one pane has the keyboard. "
                                   + "Shortcuts that act on \u{201C}the tab\u{201D} mean the "
                                   + "selected tab of the focused pane."),
                    GuideTopic("arrow.left.and.right.righttriangle.left.righttriangle.right",
                               "Resize and close",
                               "Drag a divider to change the ratio; it is remembered with the "
                                   + "layout. Closing the last tab of a pane closes the pane and "
                                   + "its sibling takes the space."),
                    GuideTopic("macwindow.on.rectangle", "A workspace in its own window",
                               "\u{201C}Move Workspace to New Window\u{201D} from the sidebar "
                                   + "context menu moves it to a window of its own, handy on a "
                                   + "second screen. Its sessions keep running through the move, "
                                   + "and each window has its own sidebar listing only its "
                                   + "workspaces."),
                ]),
                .note(
                    "Windows, panes, tabs and the divider ratios come back where you left them "
                        + "after a restart. Terminals do not: a shell cannot be resurrected, but "
                        + "an agent session can be resumed (see Agent state)."
                ),
            ]
        )
    }

    // MARK: - Sidebar

    static var sidebarSection: GuideSection {
        GuideSection(
            id: "sidebar",
            title: "The sidebar",
            symbol: "sidebar.left",
            summary: "Groups, pinning, archive, and everything you can drag.",
            blocks: [
                .paragraph(
                    "The sidebar is the list of your workspaces, and its order is real: it is "
                        + "the order you put them in, saved with the layout. Two things move a "
                        + "row - your own drag, and a workspace finishing work while you were "
                        + "looking elsewhere, which floats to the top of wherever it lives."
                ),
                .topics([
                    GuideTopic("rectangle.3.group", "Groups",
                               "A colored card around related workspaces, from a row's context "
                                   + "menu or the Workspace menu. Collapsed, the card is as tall "
                                   + "as a single row and shows one number: how many members are "
                                   + "waiting for you. A group with no members stops existing."),
                    GuideTopic("pin", "Pinning",
                               "A pinned row - or a whole pinned group - leads the list. "
                                   + "Everything else keeps its own order below."),
                    GuideTopic("archivebox", "Archive",
                               "The section at the bottom is for projects you are not on right "
                                   + "now. Archiving unpins, and an archived workspace no longer "
                                   + "floats up on activity, though a quiet dot on the header "
                                   + "tells you something happened in there."),
                ]),
                .paragraph(
                    "Four things can be dragged, and they are all the same gesture - press a row "
                        + "or a tab and move it:"
                ),
                .topics([
                    GuideTopic("arrow.up.arrow.down", "A workspace, to reorder it",
                               "Dragging across the pinned block at the top pins or unpins it."),
                    GuideTopic("rectangle.3.group", "A workspace, in or out of a group card",
                               "Dropping just inside the bottom edge of a card means joining it; "
                                   + "dropping just below means leaving it. The card has a "
                                   + "dedicated last row so the two are never the same pixel."),
                    GuideTopic("archivebox", "Anything, onto Archive",
                               "Drag it back out when the project wakes up. The Archive header is "
                                   + "always there, even when empty, so the target never moves."),
                    GuideTopic("arrow.right.doc.on.clipboard", "A tab, onto another workspace",
                               "Pull a tab out of its strip and drop it on a workspace row: it "
                                   + "moves there with its terminal still running, and the target "
                                   + "is revealed - unarchived, its card opened. Moving the last "
                                   + "tab out closes the workspace it came from."),
                ]),
                .note(
                    "The sidebar does not scroll while you drag a tab onto it, so scroll to the "
                        + "target first. Tab drops land on workspace rows, not on group headers, "
                        + "and the tab joins the focused pane of the destination."
                ),
            ]
        )
    }
}
