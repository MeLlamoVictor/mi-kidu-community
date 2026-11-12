import Foundation

// MARK: - Blobatar, portado a Swift
//
// Port de Blobatar 2.7.0 (licencia MIT, © 2026 Alain; paquete fijado por Kidual), sin dependencias. Niño pide
// plato redondo, expresión «happy» y tono 0; adulto omite expresión y tono para conservar reposo y tono sembrado.
// La misma semilla da la misma forma y los mismos colores que en Kidual: lo fijan fixtures del paquete original.
//
// Regla de Kidual para la semilla (`KidAvatar.vue`): correo prioritario, si no el nombre visible. Un llamador que ya
// haya resuelto una identidad canónica puede suministrarla a `KidualAvatar.Tipo.persona`; la librería no adivina alias.
// La identidad se convierte en clave opaca («kidual-1a2b3c4d») antes de llegar a Blobatar y no entra en el SVG.
//
// Lo que no se porta (Kidual no lo usa): animación, mirada, las demás expresiones, tintes y `traits` a mano.

public enum BlobatarEngine {

    /// Reglas de render de `web/src/js/avatar.js`: `child` conserva el dibujo legacy; `adult` usa reposo y tono libre.
    public enum Kind: String, Hashable { case child, adult }

    // MARK: Semilla (`avatarSeed` de Kidual)

    /// «  Martina  » → «kidual-97a42863». Esta capa mezcla el texto recibido; la vista sustituye vacío por «Perfil Kidual».
    public static func semilla(_ nombre: String) -> String {
        let s = normalizar(nombre.isEmpty ? "Perfil Kidual" : nombre)
        let h = mezclar(0x6A09_E667 ^ UInt32(truncatingIfNeeded: s.utf16.count), Array(s.utf8))
        let hex = String(h, radix: 16)
        return "kidual-" + String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }

    /// Identidad visual ya resuelta: primero la clave canónica explícita, luego correo, después nombre visible.
    /// No conoce alias ni los deduce; un llamador sin resolución conserva su correo original.
    static func identidadVisual(nombre: String, correo: String?, identidadCanonica: String? = nil) -> String {
        if let identidadCanonica {
            let canonica = normalizar(identidadCanonica)
            if !canonica.isEmpty { return canonica }
        }
        if let correo {
            let c = normalizar(correo)
            if !c.isEmpty { return c }
        }
        let n = recortarWeb(nombre)
        return n.isEmpty ? "Perfil Kidual" : n
    }

    /// Tono (0–359) del color de un niño: «a1»…«a4» (los de antes) o «#rrggbb». Nil si no es un color.
    static func tono(deColor color: String?) -> Double? {
        let antiguos = ["a1": "#e88a6b", "a2": "#6ea892", "a3": "#2a7a8d", "a4": "#b25d3b"]
        guard let color else { return nil }
        var hex = (antiguos[color] ?? color).trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let v = UInt32(hex, radix: 16) else { return nil }
        let r = Double((v >> 16) & 255) / 255, g = Double((v >> 8) & 255) / 255, b = Double(v & 255) / 255
        let maximo = max(r, g, b), minimo = min(r, g, b), d = maximo - minimo
        if d == 0 { return 0 }
        let h: Double
        if maximo == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if maximo == g { h = 60 * ((b - r) / d + 2) }
        else { h = 60 * ((r - g) / d + 4) }
        return redondear((h + 360).truncatingRemainder(dividingBy: 360))
    }

    // MARK: Dibujo

    /// El avatar para una identidad, respetando las opciones adult/child y el matiz explícito si existe.
    public static func dibujo(identidad: String, color: String? = nil, kind: Kind = .child) -> Dibujo {
        let colorClave = color ?? ""
        // Longitudes y kind separan identidades con delimitadores y las dos reglas de render.
        let clave = "\(kind.rawValue)|\(identidad.utf8.count):\(identidad)|\(colorClave.utf8.count):\(colorClave)" as NSString
        if let hecho = cache.object(forKey: clave) { return hecho.dibujo }
        let d = dibujo(clave: semilla(identidad), kind: kind, hue: tono(deColor: color))
        cache.setObject(Caja(d), forKey: clave)
        return d
    }

    /// Opciones exactas de `blobatar` 2.7.0: child fija happy/tone 0; adult omite ambas opciones.
    static func dibujo(clave: String, kind: Kind = .child, hue: Double? = nil) -> Dibujo {
        let t = Rasgos(clave)
        let h = hue ?? t.num("hue", 0, 360)
        let nivel = kind == .child ? 0 : t("tone")
        let p = paleta(tono: h, nivel: nivel)
        var l = composicion(t)
        if kind == .child {
            l.ojos = l.ojos.enumerated().map { i, e in Pose.feliz.aplicar(e, i) }
        }
        var cuerpo: [Dibujo.Figura] = l.petalos.map { .circulo(r2($0.cx), r2($0.cy), r2($0.r)) }
        cuerpo += l.extra.map { .trazo($0) }
        cuerpo.append(.trazo(l.trazo(l.cuerpo)))
        return Dibujo(forma: l.forma.nombre, tono: h, fondo: superelipse(Elipse(cx: 50, cy: 50, rx: 50, ry: 50), n: 2, rot: 0),
                      colorFondo: p.fondo, colorCabeza: p.cabeza, colorOjos: p.ojos, cuerpo: cuerpo,
                      ojos: l.ojos.map { superelipse(Elipse(cx: $0.cx, cy: $0.cy, rx: $0.rx, ry: $0.ry), n: $0.n, rot: $0.rot) },
                      bajada: kind == .child ? Pose.feliz.bdy : 0)
    }

    /// Lo que se pinta, en un lienzo de 100 × 100: el plato, el cuerpo (círculos y trazos del mismo color) y los ojos.
    public struct Dibujo: Hashable, Sendable {
        public enum Orden: Hashable, Sendable {
            case m(Double, Double), l(Double, Double), h(Double), v(Double)
            case c(Double, Double, Double, Double, Double, Double), q(Double, Double, Double, Double), z
        }
        public enum Figura: Hashable, Sendable { case trazo([Orden]), circulo(Double, Double, Double) }

        /// round, organic, boxy, capsule, nub, cloud, droplet, hexagon, sun o triangle.
        public var forma: String
        /// Tono (0–360) de la paleta.
        public var tono: Double
        public var fondo: [Orden]
        public var colorFondo: String, colorCabeza: String, colorOjos: String
        public var cuerpo: [Figura]
        public var ojos: [[Orden]]
        /// Lo que «happy» sube el cuerpo (`translate(0 -2.2)`).
        public var bajada: Double

        /// El mismo SVG que da Blobatar (`blobatar(clave, opciones)`); lo usan las pruebas para compararlo.
        public func svg(titulo: String? = nil, tamano: Int? = nil) -> String {
            let dim = tamano.map { " width=\"\($0)\" height=\"\($0)\"" } ?? ""
            let t = titulo.map { "<title>" + $0.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") + "</title>" } ?? ""
            let figuras = cuerpo.map { f -> String in
                switch f {
                case .trazo(let o): return "<path d=\"\(Self.d(o))\"/>"
                case .circulo(let x, let y, let r): return "<circle cx=\"\(texto(x))\" cy=\"\(texto(y))\" r=\"\(texto(r))\"/>"
                }
            }.joined()
            let ojosSVG = ojos.map { "<path d=\"\(Self.d($0))\"/>" }.joined()
            var cuerpoSVG = "<g fill=\"\(colorCabeza)\">\(figuras)</g><g fill=\"\(colorOjos)\">\(ojosSVG)</g>"
            if bajada != 0 { cuerpoSVG = "<g transform=\"translate(0 \(texto(redondear(bajada * 1000) / 1000)))\">\(cuerpoSVG)</g>" }
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"\(dim)>\(t)<path d=\"\(Self.d(fondo))\" fill=\"\(colorFondo)\"/>\(cuerpoSVG)</svg>"
        }

        public static func d(_ o: [Orden]) -> String {
            o.map { x -> String in
                switch x {
                case .m(let a, let b): return "M\(texto(a)) \(texto(b))"
                case .l(let a, let b): return "L\(texto(a)) \(texto(b))"
                case .h(let a): return "H\(texto(a))"
                case .v(let a): return "V\(texto(a))"
                case .c(let a, let b, let c, let d, let e, let f): return "C\(texto(a)) \(texto(b)) \(texto(c)) \(texto(d)) \(texto(e)) \(texto(f))"
                case .q(let a, let b, let c, let d): return "Q\(texto(a)) \(texto(b)) \(texto(c)) \(texto(d))"
                case .z: return "Z"
                }
            }.joined()
        }
    }

    // MARK: - Números como JavaScript

    /// `Math.round`: la mitad sube siempre (−2,5 → −2), no se aleja del cero como `rounded()`.
    static func redondear(_ x: Double) -> Double {
        let f = x.rounded(.down)
        return x - f >= 0.5 ? f + 1 : f
    }

    /// `Math.round(v * 100) / 100`.
    static func r2(_ v: Double) -> Double { redondear(v * 100) / 100 }

    /// `String(número)` de JavaScript para los valores del dibujo (−0 → «0», 50 → «50», 77.61 → «77.61»).
    static func texto(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v == v.rounded(.towardZero), abs(v) < 1e15 { return String(Int64(v)) }
        return "\(v)"
    }

    // MARK: - Semilla y rasgos (`hash.ts`, `traits.ts`)

    static func normalizar(_ s: String) -> String {
        recortarWeb(s.precomposedStringWithCanonicalMapping).lowercased()
    }

    /// Mismo conjunto de bordes que `String.trim()` de ECMAScript, incluida BOM y excluidos NEL y zero-width space.
    static func recortarWeb(_ s: String) -> String {
        let escalares = Array(s.unicodeScalars)
        var inicio = 0
        var fin = escalares.count
        while inicio < fin, esEspacioWeb(escalares[inicio].value) { inicio += 1 }
        while fin > inicio, esEspacioWeb(escalares[fin - 1].value) { fin -= 1 }
        return String(String.UnicodeScalarView(escalares[inicio..<fin]))
    }

    private static func esEspacioWeb(_ valor: UInt32) -> Bool {
        switch valor {
        case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    static func mezclar(_ estado: UInt32, _ bytes: [UInt8]) -> UInt32 {
        var h = estado
        for b in bytes {
            h = (h ^ UInt32(b)) &* 3_432_918_353
            h = (h << 13) | (h >> 19)
        }
        return h
    }

    /// murmur3 fmix32.
    static func finalizar(_ h0: UInt32) -> UInt32 {
        var h = (h0 ^ (h0 >> 16)) &* 2_246_822_507
        h = (h ^ (h >> 13)) &* 3_266_489_909
        return h ^ (h >> 16)
    }

    /// Cada rasgo sale de su nombre («eye.gap»), independiente de los demás.
    struct Rasgos: Sendable {
        let estado: UInt32
        init(_ semilla: String) {
            let s = BlobatarEngine.normalizar(semilla)
            estado = BlobatarEngine.mezclar(0x6A09_E667 ^ UInt32(truncatingIfNeeded: s.utf16.count), Array(s.utf8))
        }
        func callAsFunction(_ k: String) -> Double {
            Double(BlobatarEngine.finalizar(BlobatarEngine.mezclar(BlobatarEngine.mezclar(estado, [0xFF]), Array(k.utf8)))) / 4_294_967_296
        }
        func num(_ k: String, _ a: Double, _ b: Double) -> Double { a + self(k) * (b - a) }
        func int(_ k: String, _ a: Int, _ b: Int) -> Int { a + Int((self(k) * Double(b - a + 1)).rounded(.down)) }
        func jitter(_ k: String, _ a: Double) -> Double { (self(k) * 2 - 1) * a }
    }

    // MARK: - Color (`color.ts`): OKLCh con contraste mínimo

    struct Oklch: Sendable { var l: Double, c: Double, h: Double }

    private static func lineal(_ o: Oklch) -> [Double] {
        let r = o.h * .pi / 180, a = o.c * cos(r), b = o.c * sin(r)
        let l_ = o.l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = o.l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = o.l - 0.0894841775 * a - 1.291485548 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        return [4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S,
                -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S,
                -0.0041960863 * L - 0.7034186147 * M + 1.707614701 * S]
    }

    private static func dentro(_ rgb: [Double]) -> Bool { rgb.allSatisfy { $0 >= -1e-4 && $0 <= 1 + 1e-4 } }

    private static func resolver(_ o: Oklch) -> [Double] {
        var rgb = lineal(o)
        if !dentro(rgb) {
            var lo = 0.0, hi = o.c
            for _ in 0..<12 {
                let mid = (lo + hi) / 2
                if dentro(lineal(Oklch(l: o.l, c: mid, h: o.h))) { lo = mid } else { hi = mid }
            }
            rgb = lineal(Oklch(l: o.l, c: lo, h: o.h))
        }
        return rgb.map { min(1, max(0, $0)) }
    }

    private static func luminancia(_ o: Oklch) -> Double {
        let v = resolver(o)
        return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
    }

    static func contraste(_ a: Oklch, _ b: Oklch) -> Double {
        let x = luminancia(a), y = luminancia(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func conContraste(_ fg: Oklch, _ bg: Oklch, _ minimo: Double) -> Oklch {
        if contraste(fg, bg) >= minimo { return fg }
        let lado: Double = fg.l >= bg.l ? 1 : -1
        for dir in [lado, -lado] {
            var p = fg
            for _ in 0..<60 {
                p.l = min(1, max(0, p.l + dir * 0.02))
                if contraste(p, bg) >= minimo { return p }
                if p.l == 0 || p.l == 1 { break }
            }
        }
        let negro = Oklch(l: 0, c: 0, h: fg.h), blanco = Oklch(l: 1, c: 0, h: fg.h)
        return contraste(negro, bg) >= contraste(blanco, bg) ? negro : blanco
    }

    static func hex(_ o: Oklch) -> String {
        "#" + resolver(o).map { v -> String in
            let s = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
            let x = String(Int(redondear(s * 255)), radix: 16)
            return x.count < 2 ? "0" + x : x
        }.joined()
    }

    /// pastel, neutro claro, medio, hondo, vivo y tinta. Kidual pide siempre el primero (tono 0).
    private static let niveles: [(Double, Double, Double)] = [
        (0.2, 0.86, 0.085), (0.36, 0.9, 0.028), (0.62, 0.73, 0.135), (0.8, 0.62, 0.165), (0.93, 0.87, 0.16), (1.0, 0.34, 0.035),
    ]

    static func paleta(tono h: Double, nivel: Double) -> (fondo: String, cabeza: String, ojos: String) {
        let n = niveles.first { nivel < $0.0 } ?? niveles[0]
        let superficie = Oklch(l: 0.145, c: 0, h: 0)
        var cabeza = conContraste(Oklch(l: n.1, c: n.2, h: h), superficie, 1.5)
        let fondo = Oklch(l: 0.965, c: 0.01, h: h)
        var ojos = cabeza.l >= 0.5 ? Oklch(l: 0.17, c: 0.02, h: h) : Oklch(l: 0.97, c: 0.012, h: h)
        cabeza = conContraste(cabeza, fondo, 1.25)
        ojos = conContraste(ojos, cabeza, 4.5)
        return (hex(fondo), hex(cabeza), hex(ojos))
    }

    // MARK: - Trazos (`shape.ts`)

    struct Elipse: Sendable { var cx: Double, cy: Double, rx: Double, ry: Double }

    static func superelipse(_ e: Elipse, n: Double, rot: Double) -> [Dibujo.Orden] {
        let k = min(1, (8 * pow(2, -1 / n) - 4) / 3)
        let a = e.rx, b = e.ry, ak = a * k, bk = b * k
        let pts: [(Double, Double)] = [(a, 0), (a, bk), (ak, b), (0, b), (-ak, b), (-a, bk), (-a, 0),
                                       (-a, -bk), (-ak, -b), (0, -b), (ak, -b), (a, -bk), (a, 0)]
        let t = rot * .pi / 180, cs = cos(t), sn = sin(t)
        func en(_ i: Int) -> (Double, Double) {
            let (x, y) = pts[i]
            return (r2(e.cx + x * cs - y * sn), r2(e.cy + x * sn + y * cs))
        }
        var o: [Dibujo.Orden] = [.m(en(0).0, en(0).1)]
        for i in stride(from: 1, to: 13, by: 3) {
            let p = en(i), q = en(i + 1), r = en(i + 2)
            o.append(.c(p.0, p.1, q.0, q.1, r.0, r.1))
        }
        return o + [.z]
    }

    /// Curva cerrada orgánica (Catmull-Rom → Bézier) por radios muestreados.
    static func mancha(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ radios: [Double], _ rot: Double) -> [Dibujo.Orden] {
        let n = radios.count, t0 = rot * .pi / 180
        let p: [(Double, Double)] = radios.enumerated().map { i, m in
            let a = t0 + 2 * .pi * Double(i) / Double(n)
            return (cx + rx * m * cos(a), cy + ry * m * sin(a))
        }
        func en(_ i: Int) -> (Double, Double) { p[((i % n) + n) % n] }
        var o: [Dibujo.Orden] = [.m(r2(en(0).0), r2(en(0).1))]
        for i in 0..<n {
            let (x0, y0) = en(i - 1), (x1, y1) = en(i), (x2, y2) = en(i + 1), (x3, y3) = en(i + 2)
            o.append(.c(r2(x1 + (x2 - x0) / 6), r2(y1 + (y2 - y0) / 6), r2(x2 - (x3 - x1) / 6), r2(y2 - (y3 - y1) / 6), r2(x2), r2(y2)))
        }
        return o + [.z]
    }

    static func poligono(_ e: Elipse, lados: Int, redondeo: Double, rot: Double) -> [Dibujo.Orden] {
        let k = redondeo > 0 ? (redondeo < 1 ? redondeo / 2 : 0.5) : 0
        let t0 = rot * .pi / 180 - .pi / 2
        let v: [(Double, Double)] = (0..<lados).map { i in
            let a = t0 + 2 * .pi * Double(i) / Double(lados)
            return (e.cx + e.rx * cos(a), e.cy + e.ry * sin(a))
        }
        func en(_ i: Int) -> (Double, Double) { v[((i % lados) + lados) % lados] }
        func corte(_ i: Int, _ j: Int) -> (Double, Double) {
            let (x0, y0) = en(i), (x1, y1) = en(j)
            return (r2(x0 + (x1 - x0) * k), r2(y0 + (y1 - y0) * k))
        }
        let c0 = corte(0, -1)
        var o: [Dibujo.Orden] = [.m(c0.0, c0.1)]
        for i in 0..<lados {
            let (x, y) = en(i), c = corte(i, i + 1)
            o.append(.q(r2(x), r2(y), c.0, c.1))
            if k < 0.5 { let s = corte(i + 1, i); o.append(.l(s.0, s.1)) }
        }
        return o + [.z]
    }

    static func caja(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> [Dibujo.Orden] {
        let l = r2(cx - rx), r = r2(cx + rx)
        return [.m(l, r2(cy - ry)), .h(r), .v(r2(cy + ry)), .h(l), .z]
    }

    static func punta(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ tip: Double) -> [Dibujo.Orden] {
        let t = max(1.05, tip)
        let tx = rx * (1 - 1 / (t * t)).squareRoot(), ty = cy - ry / t, apex = cy - t * ry
        let px = tx * 0.14, py = ty + 0.86 * (apex - ty)
        return [.m(r2(cx - tx), r2(ty)), .l(r2(cx - px), r2(py)), .q(r2(cx), r2(apex), r2(cx + px), r2(py)), .l(r2(cx + tx), r2(ty)), .z]
    }

    // MARK: - Siluetas (`styles/shapes.ts`, `styles/blob.ts`)

    struct Cuerpo: Sendable {
        var cx: Double, cy: Double, rx: Double, ry: Double, n: Double, rot: Double, radios: [Double]
        var lados = 0, redondeo = 0.0
        var elipse: Elipse { Elipse(cx: cx, cy: cy, rx: rx, ry: ry) }
    }
    struct Petalo: Sendable { var cx: Double, cy: Double, r: Double }

    struct Forma: Sendable {
        var nombre: String
        var nucleo: Double
        var ajustar: (@Sendable (Rasgos, inout Cuerpo) -> Void)? = nil
        var cara: (@Sendable (Cuerpo) -> Elipse)? = nil
        var adornar: (@Sendable (Rasgos, Cuerpo, inout [Petalo], inout [[Dibujo.Orden]]) -> Void)? = nil
        var trazo: (@Sendable (Cuerpo) -> [Dibujo.Orden])? = nil
    }

    private static let curva: @Sendable  (Cuerpo) -> [Dibujo.Orden] = { b in mancha(b.cx, b.cy, b.rx, b.ry, b.radios, b.rot) }
    private static let poli: @Sendable  (Cuerpo) -> [Dibujo.Orden] = { b in poligono(b.elipse, lados: b.lados, redondeo: b.redondeo, rot: b.rot) }
    private static func encogida(_ k: Double) -> @Sendable (Cuerpo) -> Elipse { { b in Elipse(cx: b.cx, cy: b.cy, rx: b.rx * k, ry: b.ry * k) } }
    private static let caraCurva: @Sendable (Cuerpo) -> Elipse = { b in encogida((b.radios.min() ?? 1) * 0.95)(b) }

    /// Las diez siluetas con el borde superior de su banda (redonda y orgánica son las de diario).
    static let bandas: [(Forma, Double)] = [
        (Forma(nombre: "round", nucleo: 1), 0.22),
        (Forma(nombre: "organic", nucleo: 0.98, cara: caraCurva, trazo: curva), 0.48),
        (Forma(nombre: "boxy", nucleo: 0.86, ajustar: { t, b in b.n = t.num("body.n", 3.4, 6); b.rot = t.num("body.rot", -20, 20) }), 0.6),
        (Forma(nombre: "capsule", nucleo: 1.02,
               ajustar: { t, b in b.ry *= t.num("capsule.squat", 0.55, 0.68) },
               cara: encogida(0.94),
               adornar: { _, b, p, _ in for s in [-1.0, 1.0] { p.append(Petalo(cx: b.cx + s * (b.rx - b.ry), cy: b.cy, r: b.ry)) } },
               trazo: { b in caja(b.cx, b.cy, b.rx - b.ry, b.ry) }), 0.7),
        (Forma(nombre: "nub", nucleo: 0.88, adornar: { t, b, p, _ in
            for i in 0..<t.int("nub.n", 1, 2) {
                let a = t.num("nub.a\(i)", 0, 2 * .pi)
                p.append(Petalo(cx: b.cx + cos(a) * b.rx * 0.88, cy: b.cy + sin(a) * b.rx * 0.88, r: b.rx * t.num("nub.r\(i)", 0.24, 0.4)))
            }
        }), 0.79),
        (Forma(nombre: "cloud", nucleo: 0.78, cara: caraCurva, adornar: { t, b, p, _ in
            let n = t.int("cloud.n", 4, 6)
            for i in 0..<n {
                let a = Double.pi + Double.pi * (Double(i) + 0.5) / Double(n)
                p.append(Petalo(cx: b.cx + cos(a) * b.rx * 0.8, cy: b.cy + sin(a) * b.rx * 0.5, r: b.rx * t.num("cloud.r\(i)", 0.44, 0.62)))
            }
        }, trazo: curva), 0.86),
        (Forma(nombre: "droplet", nucleo: 0.78,
               ajustar: { _, b in b.cy += 0.22 * b.ry; b.n = 2 },
               cara: { b in Elipse(cx: b.cx, cy: b.cy + b.ry * 0.05, rx: b.rx * 0.88, ry: b.ry * 0.88) },
               adornar: { t, b, _, e in e.append(punta(b.cx, b.cy, b.rx, b.ry, t.num("droplet.tip", 1.4, 1.65))) }), 0.915),
        (Forma(nombre: "hexagon", nucleo: 1.05,
               ajustar: { t, b in b.lados = 6; b.rot = t.num("body.rot", -12, 12); b.redondeo = t.num("poly.round", 0.24, 0.5) },
               cara: encogida(0.84), trazo: poli), 0.95),
        (Forma(nombre: "sun", nucleo: 0.7, adornar: { t, b, p, _ in
            let n = t.int("sun.n", 6, 9), dist = b.rx * t.num("sun.dist", 1.0, 1.08)
            let pr = b.rx * t.num("sun.r", 0.2, 0.26), off = t.num("sun.rot", 0, 2 * .pi)
            for i in 0..<n {
                let a = off + 2 * .pi * Double(i) / Double(n)
                p.append(Petalo(cx: b.cx + cos(a) * dist, cy: b.cy + sin(a) * dist, r: pr))
            }
        }), 0.98),
        (Forma(nombre: "triangle", nucleo: 1.15,
               ajustar: { t, b in b.lados = 3; b.rot = t.num("body.rot", -5, 5); b.redondeo = t.num("poly.round", 0.24, 0.5) },
               cara: { b in Elipse(cx: b.cx, cy: b.cy + b.ry * 0.1, rx: b.rx * 0.54, ry: b.ry * 0.36) },
               trazo: poli), 1),
    ]

    struct Ojo: Sendable { var cx: Double, cy: Double, rx: Double, ry: Double, n: Double, rot: Double }

    struct Composicion {
        var forma: Forma
        var cuerpo: Cuerpo
        var petalos: [Petalo]
        var extra: [[Dibujo.Orden]]
        var ojos: [Ojo]
        func trazo(_ b: Cuerpo) -> [Dibujo.Orden] { forma.trazo?(b) ?? superelipse(b.elipse, n: b.n, rot: b.rot) }
    }

    static func composicion(_ t: Rasgos) -> Composicion {
        let v = t("shape")
        let forma = (bandas.first { v < $0.1 } ?? bandas[bandas.count - 1]).0
        let r = t.num("body.r", 31, 38) * forma.nucleo
        var b = Cuerpo(cx: 50 + t.jitter("body.x", 1.5), cy: 50 + t.jitter("body.y", 1.5), rx: r,
                       ry: r * t.num("body.ratio", 0.92, 1.08), n: t.num("body.n", 1.9, 2.5), rot: 0,
                       radios: (0..<t.int("body.pts", 6, 8)).map { 1 + t.jitter("body.r\($0)", 0.16) })
        forma.ajustar?(t, &b)
        let cara = forma.cara?(b) ?? b.elipse
        var petalos: [Petalo] = [], extra: [[Dibujo.Orden]] = []
        forma.adornar?(t, b, &petalos, &extra)
        return Composicion(forma: forma, cuerpo: b, petalos: petalos, extra: extra, ojos: ojos(t, b, cara))
    }

    /// `faceFit`: el par de ojos cabe en la cara de la silueta en los dos ejes.
    static func ojos(_ t: Rasgos, _ b: Cuerpo, _ cara: Elipse) -> [Ojo] {
        let rx = b.rx
        let er0 = t.num("eye.rx", 0.075, 0.105) * rx
        let ratio = t.num("eye.ratio", 1.9, 3.2), escala = t.num("eye.scale", 0.78, 1.24), estira = t.num("eye.stretch", 0.85, 1.18)
        let holgura = t.num("eye.gap", 0.1, 0.24) * rx
        let ancho = er0 * max(1, escala), alto = er0 * ratio * max(1, escala * estira)
        let gap0 = ancho + rx * 0.03 + holgura
        let gx = t.jitter("gaze.x", 0.09) * cara.rx, gy = t.num("gaze.y", -0.2, 0.08) * cara.ry, dy = t.jitter("eye.dy", 0.04) * cara.ry
        let alcance = hypot(ancho, alto)
        let hace = hypot((abs(gx) + gap0 + alcance) / cara.rx, (abs(gy) + abs(dy) + alcance) / cara.ry)
        let cabe = hace > 0.9 ? 0.9 / hace : 1
        let er = er0 * cabe, eyeRy = er * ratio, gap = gap0 * cabe
        let sitio = max(0, min(1, holgura / alto))
        let tope = min(12, asin(sitio) * 180 / .pi)
        let lean = t.num("eye.lean", -1, 1) * tope
        let lean2 = max(-12, min(12, lean + t.jitter("eye.lean2", 3.5)))
        let cx = cara.cx + gx * cabe, cy = cara.cy + gy * cabe
        return [Ojo(cx: cx - gap, cy: cy, rx: er, ry: eyeRy, n: t.num("eye.n", 3.5, 6), rot: lean),
                Ojo(cx: cx + gap, cy: cy + dy * cabe, rx: er * escala, ry: eyeRy * escala * estira, n: t.num("eye.n", 3.5, 6), rot: lean2)]
    }

    /// La expresión «happy» (`expression.ts`), cocida en los ojos como hace Blobatar sin animación.
    struct Pose {
        var esx, esy, tilt, edy, edx, esx2, esy2, tilt2, edy2, lock, bdy: Double
        static let feliz = Pose(esx: 1.72, esy: 0.3, tilt: 8, edy: -1.5, edx: 1.5, esx2: 0.08, esy2: 0.05, tilt2: -16, edy2: 0, lock: 1, bdy: -2.2)

        func aplicar(_ e: Ojo, _ i: Int) -> Ojo {
            let lado: Double = i == 0 ? -1 : 1, segundo: Double = i == 0 ? 0 : 1
            return Ojo(cx: e.cx + edx * lado, cy: e.cy + edy + edy2 * segundo,
                       rx: e.rx * (esx + esx2 * segundo), ry: e.ry * (esy + esy2 * segundo), n: e.n,
                       rot: e.rot * (1 - lock) + (tilt + tilt2 * segundo) * lado)
        }
    }

    // MARK: - Caché

    private final class Caja { let dibujo: Dibujo; init(_ d: Dibujo) { dibujo = d } }
    nonisolated(unsafe) private static let cache: NSCache<NSString, Caja> = {
        let c = NSCache<NSString, Caja>()
        c.countLimit = 600
        return c
    }()
}
