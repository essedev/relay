import Foundation

/// Decisione pura su **quando** un workspace ha un segnale abbastanza forte da meritare un nome
/// generato, tenendo il minimo stato per-workspace (streak del comando in foreground,
/// stabilizzazione della cwd). Estratta da `NamingController` per essere testabile senza rete né
/// store: il controller la nutre con lo stato osservato a ogni tick e reagisce alla `Decision`.
///
/// Priorità dei segnali (come prima): agente attivo -> subito; comando in foreground stabile per N
/// tick -> filtra i comandi lampo; cwd immutata per abbastanza secondi -> nomina dalla sola
/// directory. La non-azionabilità (es. cwd = home) **non** si decide qui: resta in
/// `WorkspaceNaming.prompt`, che scarta i segnali che non identificano niente.
public struct NamingTriggerPolicy: Equatable, Sendable {
    /// Soglie dei trigger. Default allineati ai valori storici del controller.
    public struct Thresholds: Equatable, Sendable {
        /// Tick consecutivi con lo stesso comando prima di nominare da esso.
        public var commandStreak: Int
        /// Secondi di cwd stabile (immutata) prima di nominare dalla sola directory.
        public var cwdStableSeconds: TimeInterval

        public init(commandStreak: Int = 2, cwdStableSeconds: TimeInterval = 10) {
            self.commandStreak = commandStreak
            self.cwdStableSeconds = cwdStableSeconds
        }
    }

    /// Esito di un tick: aspetta ancora, oppure nomina con questi segnali.
    public enum Decision: Equatable, Sendable {
        case wait
        case name(WorkspaceNameSignals)
    }

    private struct CommandStreak: Equatable {
        var command: String
        var count: Int
    }

    private struct CwdTrack: Equatable {
        var path: String
        var since: Date
    }

    private let thresholds: Thresholds
    private var streak: CommandStreak?
    private var cwd: CwdTrack?

    public init(thresholds: Thresholds = .init()) {
        self.thresholds = thresholds
    }

    /// Un tick di poll per un workspace eleggibile. `agent` è non-nil solo quando un agente è
    /// attivo
    /// (il controller inietta il nome, es. "claude"): in quel caso nomina subito, **senza** toccare
    /// lo stato di streak/cwd (così un tick successivo senza agente riparte pulito). Altrimenti
    /// aggiorna la streak del comando e la stabilizzazione della cwd e decide di conseguenza.
    public mutating func observe(
        agent: String?,
        command: String?,
        cwd: String?,
        now: Date
    ) -> Decision {
        if let agent {
            return .name(WorkspaceNameSignals(directory: cwd, command: command, agent: agent))
        }

        if let command {
            let count = (streak?.command == command ? (streak?.count ?? 0) : 0) + 1
            streak = CommandStreak(command: command, count: count)
            if count >= thresholds.commandStreak {
                return .name(WorkspaceNameSignals(directory: cwd, command: command))
            }
        } else {
            streak = nil
        }

        if let cwd {
            if self.cwd?.path != cwd {
                self.cwd = CwdTrack(path: cwd, since: now)
            } else if now.timeIntervalSince(self.cwd?.since ?? now) >= thresholds.cwdStableSeconds {
                return .name(WorkspaceNameSignals(directory: cwd))
            }
        }

        return .wait
    }
}
