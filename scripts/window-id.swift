#!/usr/bin/env swift
// Stampa il window id della finestra più grande di un processo, per `screencapture -l`.
//
// Serve a `screenshots.sh`. Due ragioni per non catturare a regione (`-R`) e non cercare per nome:
// una regione prende un rettangolo di schermo con dentro qualunque cosa ci sia sotto la finestra
// (inclusa un'altra istanza di Relay con lavoro vero), e il nome del processo non distingue la
// demo dal Relay installato. Il **pid** sì: lo script lo conosce, l'ha lanciato lui.
//
// Bounds, pid e id sono leggibili senza permessi speciali (il titolo no: richiederebbe Screen
// Recording, e infatti non lo usiamo).
//
// Uso: window-id.swift <pid>

import CoreGraphics
import Foundation

guard let pid = CommandLine.arguments.dropFirst().first.flatMap(Int.init) else {
    FileHandle.standardError.write(Data("uso: window-id.swift <pid>\n".utf8))
    exit(64)
}

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("window list non disponibile\n".utf8))
    exit(1)
}

let candidates = windows.compactMap { info -> (id: CGWindowID, area: CGFloat)? in
    guard info[kCGWindowOwnerPID as String] as? Int == pid,
          let id = info[kCGWindowNumber as String] as? CGWindowID,
          let dict = info[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
          bounds.width > 400, bounds.height > 400 // scarta pannelli, ombre e overlay
    else { return nil }
    return (id, bounds.width * bounds.height)
}

guard let biggest = candidates.max(by: { $0.area < $1.area }) else {
    FileHandle.standardError.write(Data("nessuna finestra per il pid \(pid)\n".utf8))
    exit(2)
}

print(biggest.id)
