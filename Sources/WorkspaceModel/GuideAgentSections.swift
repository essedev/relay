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
                    "Relay knows what Claude Code and Codex are doing because their native "
                        + "callbacks (hooks) report when a session starts working, asks for "
                        + "input, or finishes. Nothing is guessed from the "
                        + "terminal output, so the badges stay right even when the screen is "
                        + "full of build logs."
                ),
                .steps([
                    "Install the hooks once, from Settings > Agents or with relay-cli hooks "
                        + "setup all.",
                    "Run claude or codex in any tab. The tab is bound to that session "
                        + "automatically.",
                    "The badge on the tab, and the aggregate badge on its workspace, follow along.",
                ]),
                .command(
                    "relay-cli hooks status all",
                    note: "Check both integrations. Relay appends marked entries to Claude Code "
                        + "and Codex configuration, so your existing hooks stay in place; "
                        + "relay-cli hooks uninstall all removes only ours. Replace all with "
                        + "claude or codex to manage one agent; omitting it defaults to claude."
                ),
                .note(
                    "A Relay release can add a hook, and a configuration written by an older "
                        + "version would stay one event short without saying so. Settings and "
                        + "relay-cli hooks status name the missing events, and Relay puts back "
                        + "the ones Claude Code needs on its own at launch."
                ),
                .note(
                    "Use a Codex CLI version with native hook support. In Codex, review user "
                        + "hooks with /hooks after installation and whenever definitions change. "
                        + "Because that trust has to be renewed, Relay never rewrites the Codex "
                        + "configuration on its own: if it falls behind, Settings tells you and "
                        + "the button becomes Update. Installed means the configuration is "
                        + "present; Relay cannot check whether Codex has trusted it."
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
                                   + "quiet one: no ring, just a hollow badge. It says "
                                   + "\u{201C}you know about this, you have not "
                                   + "answered\u{201D}."),
                    GuideTopic("checkmark.circle", "Resolved: gone",
                               "Actually replying to the session clears it, and so do /clear and "
                                   + "/resume, marking it read from the sidebar, and closing "
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
                               "Claude Code reports when a turn dies on an API error - rate "
                                   + "limit, overloaded, "
                                   + "billing, no network - the turn ends without finishing. The "
                                   + "tab goes red and calls you like any other unseen signal: "
                                   + "ring, badge, a float to the top and a notification. Every "
                                   + "kind of error looks the same here; the terminal has the "
                                   + "details. Retrying clears it. Codex currently has no "
                                   + "equivalent failure hook, so those failures remain visible "
                                   + "only in its terminal output."),
                    GuideTopic("bell.badge", "Notifications",
                               "macOS notifications when a session needs input, hits an error, "
                                   + "or finishes while you are not looking at its tab. Clicking "
                                   + "one brings that tab up, wherever it is. Per-type toggles "
                                   + "and the sound are in Settings."),
                    GuideTopic("arrow.clockwise", "Resume after a restart",
                               "Terminals do not survive a restart, but agent sessions can: a "
                                   + "restored tab with a session offers a Resume bar that types "
                                   + "the resume command for you. Settings can make it automatic; "
                                   + "the default asks, because nothing should type commands into "
                                   + "your shell unannounced. Quitting hangs up every session "
                                   + "Relay started, and anything still running from a previous "
                                   + "run, such as an agent stuck past the hangup or a session "
                                   + "left behind by a crash, is stopped at launch before anything "
                                   + "resumes, so a session never runs twice."),
                    GuideTopic("moon.zzz", "Deactivate a session",
                               "An agent session costs a couple of hundred megabytes and a "
                                   + "handful of processes, and Relay never evicts a tab that "
                                   + "still has one running. Deactivate Sessions, in the "
                                   + "Workspace menu or on a sidebar row, stops them and keeps "
                                   + "the way back: the tabs stay where they are and reopening "
                                   + "one offers to resume. Tabs on screen and agents that are "
                                   + "working are left alone, and the confirmation says so. A "
                                   + "deactivated tab never resumes on its own, even with "
                                   + "automatic resume on: you can open it to look without "
                                   + "starting it again."),
                ]),
                .note(
                    "If a resume ends in command not found, something in that tab was waiting "
                        + "for input and took the first character as its answer: a resume types "
                        + "into the shell exactly as you would, it does not wait for a prompt. "
                        + "The failed line still carries the whole session id, so you can run "
                        + "the command by hand. To stop it happening, answer or silence whatever "
                        + "asks at shell startup; for the oh-my-zsh update prompt that is "
                        + "zstyle ':omz:update' mode auto in ~/.zshrc."
                ),
                .note(
                    "Notifications need a bundle identifier, so they work in the installed app, "
                        + "not when running from a development build."
                ),
            ]
        )
    }

    // MARK: - Home e Projects

    static var dashboardSection: GuideSection {
        GuideSection(
            id: "dashboard",
            title: "Home and Projects",
            symbol: "house",
            summary: "What needs you, and every project you have, open or closed.",
            blocks: [
                .paragraph(
                    "With a dozen sessions running, the question is not \u{201C}what is in this "
                        + "tab\u{201D} but \u{201C}what should I look at next\u{201D}. Home "
                        + "answers that, in place of the terminals: its title says how many "
                        + "sessions need you, and each one comes with the line the agent left "
                        + "on screen and the action it wants."
                ),
                .topics([
                    GuideTopic("exclamationmark.bubble", "Needs you",
                               "Waiting for an answer, stopped on an error, or finished and not "
                                   + "reviewed. Answer, Check or Review takes you to the tab."),
                    GuideTopic("bolt", "Working",
                               "Sessions running on their own, one compact row each."),
                    GuideTopic("moon.zzz", "Quiet for a week",
                               "Open projects that have not moved in seven days. Closing them "
                                   + "frees their terminals; their sessions stay resumable."),
                    GuideTopic("square.grid.2x2", "Projects",
                               "The catalog of every project, by group, open or closed. Filter "
                                   + "by name or folder; a click opens a closed project with its "
                                   + "tabs, ready to resume."),
                ]),
                .note(
                    "Home and Projects sit on top of the terminals without stopping them: Esc, "
                        + "or picking a project in the sidebar, takes you straight back."
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
                        + "running in one of its tabs, an agent session and the topic of its "
                        + "chat. With an agent in the tab Relay waits for the chat to get its "
                        + "title, up to a minute. The name pulses while it is being worked out."
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
                        + "key is an upgrade, not a requirement. The model sees the folder's "
                        + "name (not its path), the running command and the agent chat's title, "
                        + "nothing else."
                ),
            ]
        )
    }
}
