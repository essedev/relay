import SwiftUI

/// Posizione e lunghezza della barretta di scroll, in punti dal bordo alto del contenitore. Logica
/// pura, separata dalla view per essere testata.
struct ScrollIndicatorKnob: Equatable {
    let top: CGFloat
    let length: CGFloat

    /// `nil` quando il contenuto sta tutto nel contenitore: niente da indicare.
    /// - Parameters:
    ///   - offset: distanza scrollata dall'inizio del contenuto (0 in cima; negativa o oltre il
    ///     massimo durante il rimbalzo elastico).
    ///   - content: altezza del contenuto, insets compresi.
    ///   - viewport: altezza visibile del contenitore.
    ///   - inset: margine della barretta dai bordi alto e basso.
    ///   - minLength: lunghezza minima, per restare visibile su liste lunghe.
    init?(
        offset: CGFloat, content: CGFloat, viewport: CGFloat, inset: CGFloat, minLength: CGFloat
    ) {
        let maxOffset = content - viewport
        let track = viewport - inset * 2
        guard maxOffset > 0.5, track > 0 else { return nil }
        let full = min(track, max(minLength, track * viewport / content))
        // Nel rimbalzo la barretta si accorcia invece di uscire dalla track, come quella di
        // sistema.
        let overshoot = offset < 0 ? -offset : max(0, offset - maxOffset)
        length = max(min(minLength, full) / 2, full - overshoot)
        let progress = min(max(offset / maxOffset, 0), 1)
        top = inset + (track - length) * progress
    }
}

extension View {
    /// Sostituisce lo scroller di sistema di uno `ScrollView` verticale con una barretta sottile
    /// che compare mentre scorri e sfuma poco dopo. Lo scroller nativo (17 punti, si allarga
    /// all'hover, con la track quando le preferenze lo vogliono sempre visibile) non si può
    /// assottigliare da SwiftUI: `.controlSize` non gli arriva. Va applicato allo `ScrollView`.
    /// La barretta non si trascina: è un indicatore, non un controllo.
    func relayScrollIndicator(_ colors: ChromeColors) -> some View {
        modifier(ScrollIndicatorModifier(colors: colors))
    }
}

/// Lo stato vive nel modifier: a ogni frame di scroll si rivaluta solo questo body, non quello
/// del contenuto dello `ScrollView`.
private struct ScrollIndicatorModifier: ViewModifier {
    let colors: ChromeColors

    @State private var geometry: ScrollGeometry?
    @State private var phase: ScrollPhase = .idle
    @State private var visible = false
    @State private var hide: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            // `.never` e non `.hidden`: `.hidden` cede alla preferenza "mostra sempre" di sistema.
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }, action: { old, new in
                geometry = new
                // Solo lo scorrimento mostra la barretta: un contenuto che cresce o un resize no.
                if old.contentOffset.y != new.contentOffset.y { reveal() }
            })
            .onScrollPhaseChange { _, new in
                phase = new
                if new.isScrolling { reveal() } else { scheduleHide() }
            }
            .overlay { knob.allowsHitTesting(false) }
            .onDisappear { hide?.cancel() }
    }

    @ViewBuilder private var knob: some View {
        if let geometry, let knob = ScrollIndicatorKnob(
            offset: geometry.contentOffset.y + geometry.contentInsets.top,
            content: geometry.contentSize.height + geometry.contentInsets.top
                + geometry.contentInsets.bottom,
            viewport: geometry.containerSize.height,
            inset: Theme.Metrics.scrollIndicatorInset,
            minLength: Theme.Metrics.scrollIndicatorMinLength
        ) {
            Capsule()
                .fill(colors.scrollIndicator)
                .frame(width: Theme.Metrics.scrollIndicatorWidth, height: knob.length)
                .offset(x: -Theme.Metrics.scrollIndicatorInset, y: knob.top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .opacity(visible ? 1 : 0)
                .animation(Theme.Motion.scrollIndicatorFade, value: visible)
        }
    }

    private func reveal() {
        visible = true
        scheduleHide()
    }

    /// Riparte da capo a ogni movimento; a dito fermo sul trackpad (fase non idle) la barretta
    /// resta, e la nasconde il ritorno a idle.
    private func scheduleHide() {
        hide?.cancel()
        hide = Task { @MainActor in
            try? await Task.sleep(for: Theme.Motion.scrollIndicatorLinger)
            guard !Task.isCancelled, !phase.isScrolling else { return }
            visible = false
        }
    }
}
