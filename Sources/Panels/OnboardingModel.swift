import Foundation

/// Pagine dell'onboarding, nell'ordine di presentazione: prima il valore, poi l'unico passo
/// azionabile (gli hook, senza cui Relay è un terminale muto), poi il cuore concettuale
/// (attenzione), la navigazione e la personalizzazione.
public enum OnboardingPage: Int, CaseIterable, Identifiable, Sendable {
    case welcome, hooks, attention, navigation, customize

    public var id: Int {
        rawValue
    }
}

/// Stato di navigazione dell'onboarding: indice corrente + regole di avanzamento (clamp ai bordi,
/// niente wrap). Puro e testato; la vista lo tiene in `@State`. Nessun auto-ciclo: il testo non
/// deve muoversi sotto gli occhi di chi legge, avanza solo l'utente.
public struct OnboardingModel: Equatable, Sendable {
    public private(set) var index = 0

    public init() {}

    public var page: OnboardingPage {
        OnboardingPage.allCases[index]
    }

    public var isFirst: Bool {
        index == 0
    }

    public var isLast: Bool {
        index == OnboardingPage.allCases.count - 1
    }

    public mutating func advance() {
        index = min(index + 1, OnboardingPage.allCases.count - 1)
    }

    public mutating func back() {
        index = max(index - 1, 0)
    }

    public mutating func select(_ page: OnboardingPage) {
        index = page.rawValue
    }
}
