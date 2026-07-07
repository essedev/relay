import Foundation

/// Identità di questa run dell'app: un nonce generato una volta per processo. Iniettato nell'env
/// delle surface come `RELAY_RUN_ID` (accanto a `RELAY_TAB_ID`), ereditato da shell -> agent ->
/// hook e rimandato negli eventi. Serve a distinguere gli eventi delle sessioni di questa run da
/// quelli di sessioni orfane di run precedenti: quegli hook girano *adesso* (timestamp fresco,
/// oltre ogni soglia temporale) ma portano la run di quando la loro surface è nata.
public enum RelayRunID {
    public static let current = UUID().uuidString
}
