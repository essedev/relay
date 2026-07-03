import AppKit

/// Anteprima udibile del suono di notifica, per il picker nelle impostazioni: quando l'utente
/// sceglie un suono lo riproduce subito. I nomi (Glass, Ping, ...) sono i suoni di sistema in
/// `/System/Library/Sounds`; "Default" non e un file riproducibile, quindi ricade sul beep.
enum NotificationSoundPreview {
    static func play(_ name: String) {
        if name != "Default", let sound = NSSound(named: name) {
            sound.stop() // se stava gia suonando (cambi rapidi), riparti da capo
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
