/// Pinceles disponibles.
public enum BrushKind: String, CaseIterable, Identifiable, Sendable {
    case draw, inflate, smooth, flatten, grab

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .draw: return "Dibujar"
        case .inflate: return "Inflar"
        case .smooth: return "Suavizar"
        case .flatten: return "Aplanar"
        case .grab: return "Arrastrar"
        }
    }

    /// Nombre de icono SF Symbols.
    public var systemImage: String {
        switch self {
        case .draw: return "pencil.tip"
        case .inflate: return "balloon"
        case .smooth: return "drop"
        case .flatten: return "rectangle.compress.vertical"
        case .grab: return "hand.draw"
        }
    }

    /// Si "Invertir" tiene efecto (hundir en vez de levantar).
    public var supportsInvert: Bool { self == .draw || self == .inflate }
}

public struct SculptSettings: Equatable, Sendable {
    public var brush: BrushKind = .draw
    /// Radio del pincel en puntos de pantalla (no cambia al hacer zoom).
    public var radius: Float = 40
    /// Intensidad de 0 a 1.
    public var strength: Float = 0.5
    /// Hundir en lugar de levantar.
    public var invert = false
    /// Repetir el trazo reflejado en el plano X = 0.
    public var symmetryX = true

    public init() {}
}
