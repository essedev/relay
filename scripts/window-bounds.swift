#!/usr/bin/env swift
// Stampa "x,y,w,h" della finestra più grande di un processo, nel sistema di coordinate di
// `screencapture -R` (origine in alto a sinistra dello schermo principale, punti).
//
// Serve a `screenshots.sh` per ritagliare la finestra di Relay senza catturare il resto dello
// schermo. Usa solo bounds e pid della window list, non il titolo: leggere i titoli richiede il
// permesso Screen Recording, i bounds no.
//
// Uso: window-bounds.swift <nome-processo>

import CoreGraphics
import Foundation

let processName = CommandLine.arguments.dropFirst().first ?? "relay"

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("window list non disponibile\n".utf8))
    exit(1)
}

/// La finestra si riconosce dal nome del processo proprietario: `pgrep` non è affidabile con
/// `swift run` (il binario ha un altro nome).
let candidates = windows.compactMap { info -> CGRect? in
    guard let name = info[kCGWindowOwnerName as String] as? String,
          name.lowercased().contains(processName.lowercased()),
          let dict = info[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
          bounds.width > 200, bounds.height > 200 // scarta pannelli e ombre
    else { return nil }
    return bounds
}

guard let box = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
    FileHandle.standardError.write(Data("nessuna finestra per '\(processName)'\n".utf8))
    exit(2)
}

print("\(Int(box.minX)),\(Int(box.minY)),\(Int(box.width)),\(Int(box.height))")
