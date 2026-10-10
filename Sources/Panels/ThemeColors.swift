import Core
import SwiftUI
import WorkspaceModel

extension Color {
    /// Da colore del tema (dato puro) a SwiftUI Color.
    init(_ relay: RelayColor) {
        self.init(
            .sRGB,
            red: Double(relay.red) / 255,
            green: Double(relay.green) / 255,
            blue: Double(relay.blue) / 255
        )
    }
}

/// Colori della chrome derivati dal tema corrente, così sidebar/tab bar/badge restano coerenti col
/// terminale. I badge attingono dai colori ANSI del tema (rosso/verde/giallo/blu della palette).
struct ChromeColors {
    let theme: RelayTheme

    init(_ theme: RelayTheme) {
        self.theme = theme
    }

    var background: Color {
        Color(theme.background)
    }

    var foreground: Color {
        Color(theme.foreground)
    }

    /// Da foreground con opacità (non dall'ANSI bright black): contrasto sensato su ogni tema.
    var secondary: Color {
        Color(theme.foreground).opacity(0.6)
    }

    var selection: Color {
        Color(theme.selection)
    }

    /// Hover più tenue della selezione.
    var hover: Color {
        Color(theme.selection).opacity(0.45)
    }

    /// Fondo tenue di un pannello/carta, un gradino sotto `hover`: unifica le tinte `selection`
    /// allo
    /// 0.35 (chip di Home, pannelli dell'onboarding).
    var surface: Color {
        Color(theme.selection).opacity(0.35)
    }

    /// La cornice della finestra attorno alle card (vedi `RelayTheme.chromeFrame`).
    var frame: Color {
        Color(theme.chromeFrame)
    }

    /// La luce in cima a una card: le card sfumano da qui al fondo del tema.
    var cardTop: Color {
        Color(theme.chromeCardTop)
    }

    /// Il fondo di una card: la luce in cima (`cardTop`) che sfuma nel fondo del tema entro
    /// `height` punti, poi il fondo pieno. Così la luce non disegna mai una banda: finisce dove
    /// inizia il colore del tema.
    func cardLight(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            background
            LinearGradient(colors: [cardTop, background], startPoint: .top, endPoint: .bottom)
                .frame(height: height)
        }
    }

    /// Superficie in rilievo (palette, popover): un gradino verso il foreground, solida.
    var raised: Color {
        Color(theme.background.mixed(with: theme.foreground, 0.05))
    }

    /// Riga selezionata della sidebar (voce di navigazione o progetto): un velo del foreground,
    /// non la pillola piena della `selection`, che a confronto pesa.
    var rowSelected: Color {
        Color(theme.foreground).opacity(0.085)
    }

    /// Hover di una riga della sidebar, un gradino sotto la selezione.
    var rowHover: Color {
        Color(theme.foreground).opacity(0.045)
    }

    /// Filo che separa le righe di una pagina: presente, mai una riga disegnata.
    var hairline: Color {
        Color(theme.foreground).opacity(0.08)
    }

    /// Barretta di scroll dei pannelli: si vede sul fondo e sulle card, senza competere col testo.
    var scrollIndicator: Color {
        Color(theme.foreground).opacity(0.3)
    }

    /// Fondo incassato di un estratto di terminale dentro una pagina: più scuro del contenitore
    /// su ogni tema, come un pozzetto.
    var terminalWell: Color {
        Color.black.opacity(theme.isDark ? 0.22 : 0.045)
    }

    /// Il colore del gruppo di un progetto, o il grigio secondario se è libero.
    func tint(of workspace: Workspace, in store: WorkspaceStore) -> Color {
        guard let groupID = workspace.groupID, let group = store.group(groupID) else {
            return secondary
        }
        return self.group(group.colorIndex)
    }

    var accent: Color {
        Color(theme.ansiColor(4))
    } // blu

    var running: Color {
        Color(theme.ansiColor(4))
    } // blu
    var needsInput: Color {
        Color(theme.ansiColor(3))
    } // giallo/ambra
    var error: Color {
        Color(theme.ansiColor(1))
    } // rosso
    var completed: Color {
        Color(theme.ansiColor(2))
    } // verde

    /// Tinta di un gruppo della sidebar: un colore ANSI del tema (vedi
    /// `WorkspaceGroup.colorIndices`), non una palette a parte, così le card seguono il tema come
    /// badge e ring.
    func group(_ colorIndex: Int) -> Color {
        Color(theme.ansiColor(colorIndex))
    }
}
