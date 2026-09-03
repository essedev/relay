import Foundation

/// Le sezioni della guida sulla parte agente: stato, triage, nomina automatica. È il motivo per cui
/// Relay esiste, quindi qui la guida è più esplicita che altrove su cosa accende e cosa spegne un
/// segnale. Contenuto, non logica (vedi `Guide.swift`).
extension Guide {
    // MARK: - Agent state

    static var agentStateSection: GuideSection {
        GuideSection(
            id: "agents",
            title: "Agent state",
            symbol: "dot.radiowaves.left.and.right",
            summary: "What your sessions are doing, and what is waiting for you.",
            blocks: [
                .paragraph(
                    "Relay knows what Claude Code is doing because Claude Code tells it: small "
                        + "callbacks (hooks) report when a session starts working, asks for "
                        + "input, finishes, or dies on an API error. Nothing is guessed from the "
                        + "terminal output, so the badges stay right even when the screen is "
                        + "full of build logs."
                ),
                .steps([
                    "Install the hooks once, from Settings > Agents or with relay-cli hooks setup.",
                    "Run claude in any tab. The tab is bound to that session automatically.",
                    "The badge on the tab, and the aggregate badge on its workspace, follow along.",
                ]),
                .command(
                    "relay-cli hooks status",
                    note: "Check what is installed. The hooks are appended to your Claude Code "
                        + "settings and marked as Relay's, so they coexist with hooks you already "
                        + "have; relay-cli hooks uninstall removes only ours."
                ),
                .paragraph(
                    "Attention is a separate thing from state. A session that finished is not "
                        + "news forever, and Relay says so in three steps rather than with one "
                        + "badge that stays until you click it:"
                ),
                .topics([
                    GuideTopic("circle.fill", "Unseen: it wants you",
                               "A ring around the terminal and a full badge on the tab. Its "
                                   + "workspace also floats to the top of the sidebar, so you "
                                   + "find it without looking."),
                    GuideTopic("circle", "Pending: seen, not picked up",
                               "Typing in a terminal you are looking at demotes its signal to a "
                                   + "quiet one: no ring, a hollow badge, still listed in the "
                                   + "dashboard. It says \u{201C}you know about this, you have "
                                   + "not answered\u{201D}."),
                    GuideTopic("checkmark.circle", "Resolved: gone",
                               "Actually replying to the session clears it, and so do /clear and "
                                   + "/resume, dismissing the card in the dashboard, and closing "
                                   + "the tab. A pending signal also fades on its own after "
                                   + "twelve hours, which you can change or switch off."),
                ]),
                .paragraph(
                    "Navigating does not count as reading: switching tabs in a strip or clicking "
                        + "a row in the sidebar leaves the signal alone. Only working inside the "
                        + "terminal does. When you disagree, the context menu has Mark as Read "
                        + "and Mark as Unread on the tab."
                ),
                .topics([
                    GuideTopic("exclamationmark.triangle", "Errors stop the session",
                               "When a turn dies on an API error - rate limit, overloaded, "
                                   + "billing, no network - the turn ends without finishing. The "
                                   + "tab goes red and calls you like any other unseen signal: "
                                   + "ring, badge, a float to the top and a notification. Every "
                                   + "kind of error looks the same here; the terminal has the "
                                   + "details. Retrying clears it."),
                    GuideTopic("bell.badge", "Notifications",
                               "macOS notifications when a session needs input, hits an error, "
                                   + "or finishes while you are not looking at its tab. Clicking "
                                   + "one brings that tab up, wherever it is. Per-type toggles "
                                   + "and the sound are in Settings."),
                    GuideTopic("arrow.clockwise", "Resume after a restart",
                               "Terminals do not survive a restart, but Claude sessions can: a "
                                   + "restored tab with a session offers a Resume bar that types "
                                   + "the resume command for you. Settings can make it automatic; "
                                   + "the default asks, because nothing should type commands into "
                                   + "your shell unannounced."),
                ]),
                .note(
                    "Notifications need a bundle identifier, so they work in the installed app, "
                        + "not when running from a development build."
                ),
            ]
        )
    }

    // MARK: - Dashboard

    static var dashboardSection: GuideSection {
        GuideSection(
            id: "dashboard",
            title: "The dashboard",
            symbol: "rectangle.grid.2x2",
            summary: "Every session in one panel, sorted by what needs you.",
            blocks: [
                .paragraph(
                    "With a dozen sessions running, the question is not \u{201C}what is in this "
                        + "tab\u{201D} but \u{201C}what should I look at next\u{201D}. The "
                        + "dashboard answers that: every session in the app, across every window "
                        + "and workspace, on one screen."
                ),
                .topics([
                    GuideTopic("rectangle.split.3x1", "Four lanes",
                               "Needs You, Running, Done and Idle. The lanes are always there, "
                                   + "so an empty one is information too."),
                    GuideTopic("square.grid.3x2", "Or a flat grid",
                               "The toggle in the header switches to a single list ordered by "
                                   + "urgency. Relay remembers which one you prefer."),
                    GuideTopic("magnifyingglass", "Type to filter",
                               "The field takes focus when the panel opens: type, use the arrow "
                                   + "keys, press Return to jump to a session and Esc to leave."),
                    GuideTopic("xmark.circle", "Dismiss",
                               "Clearing a card's signal from here is the same as marking it "
                                   + "read: it does not touch the session, only what Relay is "
                                   + "asking of you."),
                ]),
                .note(
                    "The cards are built from state, not from live terminals, so sessions in "
                        + "tabs that Relay has unloaded to save memory are listed like any other."
                ),
            ]
        )
    }

    // MARK: - Automatic naming

    static var namingSection: GuideSection {
        GuideSection(
            id: "naming",
            title: "Automatic naming",
            symbol: "text.badge.checkmark",
            summary: "A workspace takes its name from what is happening in it.",
            blocks: [
                .paragraph(
                    "A workspace opened without a folder is called \u{201C}Workspace 3\u{201D}, "
                        + "which tells you nothing when there are nine of them. Relay renames it "
                        + "after what it is actually doing: the folder you cd into, a command "
                        + "running in one of its tabs, an active agent session. The name pulses "
                        + "while it is being worked out."
                ),
                .paragraph(
                    "Out of the box the name is derived from those signals - "
                        + "\u{201C}yellow-hub\u{201D} becomes \u{201C}Yellow Hub\u{201D}, "
                        + "\u{201C}npm run dev\u{201D} becomes \u{201C}Npm Dev\u{201D}. No key, "
                        + "no network, no wait."
                ),
                .steps([
                    "Open Settings > Agents > Workspace naming for the switch.",
                    "Optional: paste an API key to have a model write the names instead. The "
                        + "default endpoint is OpenRouter; any OpenAI-compatible base URL and "
                        + "model work.",
                    "\u{201C}Regenerate name\u{201D} in a workspace's context menu asks for "
                        + "another one right away. Without a key the names are derived by rule, "
                        + "so there is often only one to give.",
                ]),
                .paragraph(
                    "A name you typed yourself is never overwritten: renaming a workspace by "
                        + "hand opts it out for good. A placeholder or a folder name is fair "
                        + "game, and once named the workspace is left alone."
                ),
                .note(
                    "The key is stored in a file only you can read, not in the preferences "
                        + "plist. A name is a couple of hundred tokens on a cheap default model, "
                        + "but it is your account - and the derived names cost nothing, so the "
                        + "key is an upgrade, not a requirement."
                ),
            ]
        )
    }
}
