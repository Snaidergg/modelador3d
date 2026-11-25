# Modelador 3D (iPhone)

App de iOS para crear y editar modelos 3D a partir de fotos o escaneos, pensada para imprimirlos en 3D.
Dispositivo objetivo: **iPhone 16 Pro Max** (LiDAR, A18 Pro). Requiere iOS 17 o superior.

Se desarrolla **desde Windows, sin Mac**. GitHub Actions compila en una máquina macOS en la nube
y entrega un `.ipa` que se instala en el iPhone con Sideloadly o AltStore.

---

## Estructura

```
modelador3d/
├── project.yml                 Definición del proyecto Xcode (XcodeGen lo convierte en .xcodeproj)
├── App/                        La app (SwiftUI): pantallas y estado
│   ├── Modelador3DApp.swift    Punto de entrada
│   ├── ContentView.swift       Pantalla principal: visor + barra de herramientas
│   ├── Editor/
│   │   ├── EditorModel.swift   Estado del editor (MVVM)
│   │   ├── EditCommands.swift  Operaciones + deshacer/rehacer (patrón Comando)
│   │   ├── InspectorView.swift Panel de medidas e imprimibilidad
│   │   └── MeshFileDocument.swift  Exportación a "Archivos"
│   ├── Capture/                Escaneo guiado, fotos, video y reconstrucción 3D
│   └── Viewport/
│       └── MetalViewport.swift Puente SwiftUI ↔ Metal y gestos táctiles
├── Packages/M3DKit/            Núcleo, en módulos independientes y con pruebas
│   ├── Sources/Geometry/       Malla, caja envolvente, primitivas, soldado de vértices
│   ├── Sources/MeshIO/         STL (binario/ASCII) y OBJ
│   ├── Sources/Rendering/      Render en Metal y cámara orbital
│   ├── Sources/PrintPrep/      Análisis de imprimibilidad (estanqueidad, volumen, normales)
│   ├── Sources/Sculpt/         Pinceles de escultura y simetría
│   └── Tests/                  Pruebas automáticas (se ejecutan en cada compilación)
└── .github/workflows/          Compilación en la nube → .ipa
```

Módulos planeados para las siguientes fases: `Capture` (fotos guiadas, escaneo con LiDAR, video),
`Reconstruction` (Object Capture en el iPhone y opción de servidor), `Sculpt` (pinceles),
`PolyEdit` y `CAD` (booleanas, primitivas paramétricas), y exportación 3MF.

### Convenciones
- Unidad interna: **milímetros**. Eje vertical interno: **+Y**.
- Al exportar STL se convierte a **+Z arriba**, que es lo que esperan los slicers (Cura, PrusaSlicer, Bambu Studio).
- En el visor, las caras traseras se ven **rojizas**: indica normales invertidas o una malla abierta.

---

## Flujo de trabajo

1. Editar el código en Windows (VS Code con la extensión *Swift* da colores y autocompletado básico).
2. `git push` a la rama `main` de GitHub.
3. En GitHub → pestaña **Actions** → la ejecución más reciente → sección **Artifacts** → descargar `Modelador3D-ipa`
   (es un `.zip` que contiene el `.ipa`).
4. Instalar el `.ipa` en el iPhone (ver abajo).

Si la compilación falla, el registro de **Actions** muestra el error exacto (archivo y línea).

> **Minutos de GitHub Actions.** En un repositorio **público** son ilimitados. En uno **privado**, los
> 2000 minutos gratuitos al mes cuentan ×10 en macOS (≈200 minutos reales, unas 25–35 compilaciones).

---

## Instalar en el iPhone

### Una sola vez
1. En el PC: instalar **iTunes** e **iCloud** descargados desde la web de Apple
   (si las versiones de Microsoft Store dan problemas, usar las de la web).
2. Instalar **Sideloadly** (sideloadly.io).
3. En el iPhone, tras el primer intento de instalación: **Ajustes → Privacidad y seguridad → Modo de desarrollador** → activar y reiniciar.

### Cada instalación
1. Conectar el iPhone por cable y aceptar "Confiar en este ordenador".
2. Abrir Sideloadly, arrastrar el `.ipa`, escribir tu Apple ID y pulsar **Start**.
3. La primera vez: **Ajustes → General → VPN y gestión de dispositivos** → confiar en tu Apple ID.

Con un Apple ID gratuito la firma dura **7 días** (máximo 3 apps instaladas así).
Para no reinstalar a mano: **AltStore** (con AltServer en el PC en la misma red Wi-Fi) renueva la firma automáticamente.
Con la cuenta de desarrollador de Apple (99 USD/año) la firma dura un año.

---

## Pruebas del núcleo

Se ejecutan solas en GitHub Actions. En una Mac (o en Linux con Swift):

```
swift test --package-path Packages/M3DKit
```

## Estado actual (v0.3)
- **Captura 3D** (botón de la cámara), reconstrucción en el propio iPhone con Object Capture de Apple:
  escaneo guiado (LiDAR), desde 20–200 fotos de la fototeca, o desde un video (extrae fotogramas).
  El modelo se abre en el editor en mm; las capturas se guardan en *Archivos → Modelador 3D → Capturas*.
- Importar USDZ y PLY además de STL/OBJ. Girar 90° en X/Y/Z.
- Visor 3D en Metal: girar (1 dedo), desplazar (2 dedos), zoom (pellizcar), encuadrar (doble toque).
- **Escultura digital** (botón del pincel): Dibujar, Inflar, Suavizar, Aplanar y Arrastrar;
  tamaño e intensidad; Hundir (invertir); simetría en X; "Más detalle" (subdividir ×4).
  En modo esculpir, un dedo fuera del modelo gira la cámara. Cada trazo se deshace de una vez.
- Base para esculpir: esfera geodésica de 40 mm y 20 480 triángulos.
- Nueva esfera o cubo; importar STL/OBJ; exportar STL binario.
- Medidas en mm, volumen, superficie y diagnóstico de imprimibilidad.
- Escalar a una altura en mm, apoyar en la cama, soldar vértices, invertir normales, subdividir.
- Deshacer/rehacer.

## Próximas fases
1. Limpieza de capturas: recortar el suelo/fondo y cerrar agujeros para que sea imprimible.
2. Mejoras de escultura: cursor del pincel, remallado por vóxeles, aceleración (BVH) para mallas grandes.
3. Booleanas y primitivas paramétricas (bases, agujeros, encastres).
4. Exportación 3MF y reparación automática de mallas.
