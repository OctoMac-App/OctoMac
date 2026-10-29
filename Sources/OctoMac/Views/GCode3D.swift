import AppKit
import MetalKit
import OctoPrintKit
import simd
import SwiftUI

// A 3D view of a toolpath, drawn with Metal. Every printing move becomes a small box the width of the nozzle and the
// height of its layer, generated on the GPU from one compact record per move (instanced drawing), so a few hundred
// thousand moves stay smooth to rotate.

struct GCode3DView: NSViewRepresentable {
    let path: GCodeToolpath
    let bed: CGRect
    let maxLayer: Int
    /// While printing: the move the printer is on. Everything after it is drawn as a faint "not printed yet" ghost,
    /// and a nozzle glides along the toolpath to it.
    var liveSegment: Int? = nil
    /// The print speed factor (1 = 100%), so the nozzle keeps pace with the printer.
    var printSpeed: Double = 1
    let hidden: Set<GCodeToolpath.Feature>
    let nozzleWidth: Float
    /// Changing this resets the camera.
    let resetToken: Int

    func makeNSView(context: Context) -> OrbitMTKView {
        let view = OrbitMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        guard let renderer = GCodeRenderer(view: view) else { return view }
        context.coordinator.renderer = renderer
        view.renderer = renderer
        view.delegate = renderer
        renderer.load(path, bed: bed)
        apply(to: renderer, view: view)
        return view
    }

    func updateNSView(_ view: OrbitMTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            renderer.resetCamera()
        }
        apply(to: renderer, view: view)
    }

    private func apply(to renderer: GCodeRenderer, view: MTKView) {
        renderer.maxLayer = maxLayer
        renderer.printSpeed = printSpeed
        renderer.setLive(target: liveSegment, view: view)
        renderer.hiddenMask = hidden.reduce(0) { $0 | (1 << UInt32($1.rawValue)) }
        renderer.halfWidth = nozzleWidth / 2
        view.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: GCodeRenderer?
        var resetToken = 0
    }
}

/// MTKView that turns mouse and trackpad input into camera moves and only redraws when something changes.
final class OrbitMTKView: MTKView {
    weak var renderer: GCodeRenderer?

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        isPaused = true
        enableSetNeedsDisplay = true
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = 4
        clearColor = MTLClearColor(red: 0.098, green: 0.110, blue: 0.129, alpha: 1)
        layer?.isOpaque = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    // Redraw when the view gets its real size (it only draws on demand).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var lastPoint: NSPoint?

    /// Movement since the last event, from pointer positions (more reliable than the event's own deltas).
    private func delta(_ event: NSEvent) -> (Float, Float) {
        let point = event.locationInWindow
        defer { lastPoint = point }
        guard let last = lastPoint else { return (0, 0) }
        // Window coordinates have Y up; the camera code expects screen-style deltas (Y down).
        return (Float(point.x - last.x), Float(last.y - point.y))
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = event.locationInWindow
        if event.clickCount == 2 { renderer?.resetCamera(); needsDisplay = true }
    }

    override func rightMouseDown(with event: NSEvent) { lastPoint = event.locationInWindow }
    override func otherMouseDown(with event: NSEvent) { lastPoint = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        let (dx, dy) = delta(event)
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift) {
            renderer?.pan(dx: dx, dy: dy, viewHeight: Float(bounds.height))
        } else {
            renderer?.orbit(dx: dx, dy: dy)
        }
        needsDisplay = true
    }

    override func rightMouseDragged(with event: NSEvent) {
        let (dx, dy) = delta(event)
        renderer?.pan(dx: dx, dy: dy, viewHeight: Float(bounds.height))
        needsDisplay = true
    }

    override func otherMouseDragged(with event: NSEvent) { rightMouseDragged(with: event) }

    override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1)
        renderer?.zoom(by: exp(-delta))
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        renderer?.zoom(by: 1 / (1 + Float(event.magnification)))
        needsDisplay = true
    }
}

// MARK: - Renderer

@MainActor
final class GCodeRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let segmentPipeline: MTLRenderPipelineState
    private let ghostPipeline: MTLRenderPipelineState
    private let bedPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let ghostDepthState: MTLDepthStencilState
    private let nozzlePipeline: MTLRenderPipelineState
    private let nozzleBuffer: MTLBuffer?
    private let nozzleVertexCount: Int
    private var segmentBuffer: MTLBuffer?
    private var segmentCount = 0

    private var path = GCodeToolpath()
    /// For each move, how many drawn (non-travel) moves come before it. Maps a move to its instance in the buffer.
    private var instancesBefore: [Int32] = []
    /// Height of each move's layer.
    private var segmentZ: [Float] = []

    // Live printing: the nozzle travels along the toolpath in real time (see `LivePlayhead`).
    private var liveTarget: Int?
    private let playhead = LivePlayhead()
    var printSpeed: Double {
        get { playhead.speed }
        set { playhead.speed = newValue }
    }

    var maxLayer = 0
    var hiddenMask: UInt32 = 0
    var halfWidth: Float = 0.225
    private var bed = CGRect(x: 0, y: 0, width: 200, height: 200)
    private var modelCenter = SIMD3<Float>(100, 100, 10)
    private var modelRadius: Float = 120

    private var target = SIMD3<Float>(0, 0, 0)
    private var distance: Float = 300
    private var azimuth: Float = -.pi / 2.6
    private var elevation: Float = 0.62

    init?(view: MTKView) {
        guard let device = view.device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            func pipeline(_ vertex: String, _ fragment: String, blended: Bool = false) throws -> MTLRenderPipelineState {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: vertex)
                descriptor.fragmentFunction = library.makeFunction(name: fragment)
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                if blended {
                    let attachment = descriptor.colorAttachments[0]!
                    attachment.isBlendingEnabled = true
                    attachment.sourceRGBBlendFactor = .sourceAlpha
                    attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    attachment.sourceAlphaBlendFactor = .one
                    attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
                descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
                descriptor.rasterSampleCount = view.sampleCount
                return try device.makeRenderPipelineState(descriptor: descriptor)
            }
            segmentPipeline = try pipeline("segmentVertex", "segmentFragment")
            ghostPipeline = try pipeline("segmentVertex", "ghostFragment", blended: true)
            bedPipeline = try pipeline("bedVertex", "bedFragment")
            nozzlePipeline = try pipeline("nozzleVertex", "nozzleFragment")
        } catch {
            NSLog("OctoMac: Metal setup failed: \(error)")
            return nil
        }
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        // Ghosts are tested against the solid print but don't hide each other.
        let ghostDepth = MTLDepthStencilDescriptor()
        ghostDepth.depthCompareFunction = .less
        ghostDepth.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depth),
              let ghostDepthState = device.makeDepthStencilState(descriptor: ghostDepth) else { return nil }
        self.depthState = depthState
        self.ghostDepthState = ghostDepthState
        let mesh = NozzleMesh.make()
        nozzleVertexCount = mesh.count / 10
        nozzleBuffer = device.makeBuffer(bytes: mesh, length: mesh.count * 4, options: .storageModeShared)
        super.init()
    }

    /// Packs the printing moves (travel is never drawn in 3D) into one GPU buffer: x0, y0, x1, y1, z, height, layer, feature.
    func load(_ path: GCodeToolpath, bed: CGRect) {
        self.bed = bed
        self.path = path
        playhead.load(path)
        var floats: [Float] = []
        floats.reserveCapacity(path.segments.count * 8)
        instancesBefore = [Int32](repeating: 0, count: path.segments.count)
        segmentZ = [Float](repeating: 0, count: path.segments.count)
        var previousZ: Float = 0
        var drawn: Int32 = 0
        for (index, layer) in path.layers.enumerated() {
            let height = max(0.05, min(0.6, index == 0 ? layer.z : layer.z - previousZ))
            previousZ = layer.z
            for i in layer.segments {
                instancesBefore[i] = drawn
                segmentZ[i] = layer.z
                let s = path.segments[i]
                guard s.feature != .travel else { continue }
                floats.append(contentsOf: [s.x0, s.y0, s.x1, s.y1, layer.z, height, Float(index), Float(s.feature.rawValue)])
                drawn += 1
            }
        }
        segmentCount = floats.count / 8
        segmentBuffer = floats.isEmpty ? nil : device.makeBuffer(bytes: floats, length: floats.count * 4, options: .storageModeShared)

        // Frame the model itself: purge lines ("Custom") and skirts sit at the bed's edge and would shrink it.
        var minX = Float.infinity, minY = Float.infinity, maxX = -Float.infinity, maxY = -Float.infinity
        for s in path.segments where s.feature != .travel && s.feature != .custom && s.feature != .skirt {
            minX = min(minX, s.x0, s.x1); maxX = max(maxX, s.x0, s.x1)
            minY = min(minY, s.y0, s.y1); maxY = max(maxY, s.y0, s.y1)
        }
        let b = minX <= maxX ? (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
            : (path.bounds ?? (Float(bed.minX), Float(bed.minY), Float(bed.maxX), Float(bed.maxY)))
        let top = path.layers.last?.z ?? 10
        modelCenter = SIMD3((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2, top / 2)
        modelRadius = max(20, simd_length(SIMD3(b.maxX - b.minX, b.maxY - b.minY, top)) / 2)
        resetCamera()
    }

    /// The move OctoPrint has sent up to; the nozzle travels towards it at the printer's pace.
    func setLive(target: Int?, view: MTKView) {
        let wasLive = liveTarget != nil
        guard let target, !path.segments.isEmpty else {
            liveTarget = nil
            playhead.setTarget(nil)
            if wasLive { view.isPaused = true; view.enableSetNeedsDisplay = true }
            return
        }
        let clamped = min(target, path.segments.count - 1)
        guard clamped != liveTarget else { return }
        playhead.setTarget(clamped)
        liveTarget = clamped
        if !wasLive {
            // While live, draw continuously so the nozzle glides.
            view.enableSetNeedsDisplay = false
            view.preferredFramesPerSecond = 60
            view.isPaused = false
        }
    }

    func resetCamera() {
        target = modelCenter
        distance = modelRadius * 3.4
        azimuth = -.pi / 2.6
        elevation = 0.62
    }

    func orbit(dx: Float, dy: Float) {
        azimuth -= dx * 0.008
        elevation = max(-0.15, min(1.52, elevation + dy * 0.008))
    }

    func pan(dx: Float, dy: Float, viewHeight: Float) {
        let (right, up, _) = basis()
        let unitsPerPoint = 2 * distance * tan(fov / 2) / max(1, viewHeight)
        target += (-right * dx + up * dy) * unitsPerPoint
    }

    func zoom(by factor: Float) {
        distance = max(modelRadius * 0.15, min(modelRadius * 12, distance * factor))
    }

    private let fov: Float = 35 * .pi / 180

    private var eye: SIMD3<Float> {
        target + distance * SIMD3(cos(elevation) * cos(azimuth), cos(elevation) * sin(azimuth), sin(elevation))
    }

    private func basis() -> (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>) {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 0, 1)))
        let up = simd_cross(right, forward)
        return (right, up, forward)
    }

    // MARK: Drawing

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(view) }
    }

    private func render(_ view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }

        let aspect = Float(max(1, view.drawableSize.width) / max(1, view.drawableSize.height))
        let viewProj = perspective(fovy: fov, aspect: aspect, near: max(0.5, distance * 0.01), far: distance * 10 + 2000)
            * lookAt(eye: eye, target: target, up: SIMD3(0, 0, 1))
        // Live position: ease along the toolpath towards the latest reported move.
        var cutoff: Float = -1, printedLayer: Float = -1
        var nozzle: SIMD3<Float>?
        if liveTarget != nil, let displayed = playhead.position() {
            let index = max(0, min(path.segments.count - 1, Int(displayed)))
            let fraction = Float(displayed - Double(index))
            let s = path.segments[index]
            nozzle = SIMD3(s.x0 + (s.x1 - s.x0) * fraction, s.y0 + (s.y1 - s.y0) * fraction, segmentZ[index])
            // The current move counts as printed once the nozzle is on it.
            cutoff = Float(instancesBefore[index]) + (s.feature == .travel ? 0 : 1)
            printedLayer = Float(path.layerIndex(ofSegment: index) ?? 0)
        }

        var uniforms = Self.flatten(viewProj)
        let e = eye
        uniforms += [e.x, e.y, e.z, halfWidth]
        uniforms += [Float(maxLayer), Float(hiddenMask), cutoff, 0]
        uniforms += [Float(bed.minX), Float(bed.minY), Float(bed.maxX), Float(bed.maxY)]
        uniforms += [printedLayer, nozzle?.x ?? 0, nozzle?.y ?? 0, nozzle?.z ?? 0]
        for feature in GCodeToolpath.Feature.allCases {
            let c = NSColor(feature.color).usingColorSpace(.sRGB) ?? .gray
            uniforms += [Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1]
        }
        while uniforms.count < 16 + 16 + 16 * 4 { uniforms.append(0) }

        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)

        // Bed plane with a grid
        encoder.setRenderPipelineState(bedPipeline)
        encoder.setVertexBytes(uniforms, length: uniforms.count * 4, index: 1)
        encoder.setFragmentBytes(uniforms, length: uniforms.count * 4, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // Every printing move as an instanced box (6 faces of 2 triangles). Printed moves first, solid; then, while
        // printing, the moves still to come as a faint translucent ghost that doesn't hide the current layer.
        if let segmentBuffer, segmentCount > 0 {
            encoder.setVertexBuffer(segmentBuffer, offset: 0, index: 0)
            for ghostPass in cutoff >= 0 ? [false, true] : [false] {
                uniforms[16 + 4 + 3] = ghostPass ? 1 : 0
                encoder.setRenderPipelineState(ghostPass ? ghostPipeline : segmentPipeline)
                encoder.setDepthStencilState(ghostPass ? ghostDepthState : depthState)
                encoder.setVertexBytes(uniforms, length: uniforms.count * 4, index: 1)
                encoder.setFragmentBytes(uniforms, length: uniforms.count * 4, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: segmentCount)
            }
        }

        // The nozzle, unless the slider has cut the view below the layer being printed.
        if nozzle != nil, printedLayer <= Float(maxLayer), let nozzleBuffer {
            uniforms[16 + 4 + 3] = 0
            encoder.setRenderPipelineState(nozzlePipeline)
            encoder.setDepthStencilState(depthState)
            encoder.setVertexBuffer(nozzleBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(uniforms, length: uniforms.count * 4, index: 1)
            encoder.setFragmentBytes(uniforms, length: uniforms.count * 4, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: nozzleVertexCount)
        }

        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    // MARK: Maths

    private static func flatten(_ m: simd_float4x4) -> [Float] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    private func perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovy / 2), x = y / aspect, z = far / (near - far)
        return simd_float4x4(columns: (SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0)))
    }

    private func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(target - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }

    // MARK: Shaders

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4x4 viewProj;
        float4 eyeHalf;     // eye.xyz, half the bead width
        float4 params;      // max layer, hidden feature mask, printed-move cutoff (-1 when not printing), 1 in the ghost pass
        float4 bed;         // minX, minY, maxX, maxY
        float4 live;        // layer being printed, nozzle x, y, z
        float4 colors[16];
    };

    struct Segment { float x0, y0, x1, y1, z, h, layer, feature; };

    struct VOut {
        float4 position [[position]];
        float3 world;
        float3 normal;
        float3 color;
        float top;          // 1 for the highlighted layer
    };

    constant uint2 faceCorners[6] = { uint2(0,0), uint2(1,0), uint2(0,1), uint2(0,1), uint2(1,0), uint2(1,1) };

    vertex VOut segmentVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                              const device Segment* segments [[buffer(0)]],
                              constant Uniforms& u [[buffer(1)]]) {
        Segment s = segments[iid];
        VOut out;
        uint feature = uint(s.feature);
        bool notPrintedYet = u.params.z >= 0 && float(iid) >= u.params.z;
        bool ghostPass = u.params.w > 0.5;
        if (s.layer > u.params.x + 0.5 || ((uint(u.params.y) >> feature) & 1u) != 0u || notPrintedYet != ghostPass) {
            out.position = float4(0, 0, 2, 1);   // outside the clip volume: not drawn
            return out;
        }
        float hw = u.eyeHalf.w;
        float2 a = float2(s.x0, s.y0), b = float2(s.x1, s.y1);
        float2 d = b - a;
        float len = length(d);
        float2 dir = len > 1e-5 ? d / len : float2(1, 0);
        float2 side = float2(-dir.y, dir.x);
        // Extend each bead a little past its ends so consecutive moves join without gaps.
        a -= dir * hw * 0.7;
        b += dir * hw * 0.7;

        uint face = vid / 6;
        uint2 q = faceCorners[vid % 6];
        float t = float(q.x), v = float(q.y);
        float2 along = mix(a, b, t);
        float zTop = s.z, zBottom = s.z - s.h;
        float3 p, n;
        if (face == 0) { p = float3(along + side * (v * 2 - 1) * hw, zTop); n = float3(0, 0, 1); }
        else if (face == 1) { p = float3(along + side * (v * 2 - 1) * hw, zBottom); n = float3(0, 0, -1); }
        else if (face == 2) { p = float3(along + side * hw, mix(zBottom, zTop, v)); n = float3(side, 0); }
        else if (face == 3) { p = float3(along - side * hw, mix(zBottom, zTop, v)); n = float3(-side, 0); }
        else {
            // End caps
            float2 end = face == 4 ? a : b;
            p = float3(end + side * (t * 2 - 1) * hw, mix(zBottom, zTop, v));
            n = float3(face == 4 ? -dir : dir, 0);
        }
        out.position = u.viewProj * float4(p, 1);
        out.world = p;
        out.normal = n;
        out.color = u.colors[feature].rgb;
        bool printing = u.params.z >= 0;
        float highlight = printing ? u.live.x : u.params.x;
        out.top = abs(s.layer - highlight) < 0.5 ? 1.0 : 0.0;
        return out;
    }

    fragment float4 segmentFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
        float3 n = normalize(in.normal);
        float3 toEye = normalize(u.eyeHalf.xyz - in.world);
        float3 sun = normalize(float3(-0.35, -0.55, 0.75));
        float diffuse = 0.55 * abs(dot(n, sun)) + 0.30 * abs(dot(n, toEye));
        float3 color = in.color * (0.28 + diffuse);
        color = mix(color, min(color * 1.35 + 0.08, float3(1.0)), in.top);
        return float4(color, 1);
    }

    // Not printed yet: a faint glass-like outline of the rest of the part.
    fragment float4 ghostFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
        float3 n = normalize(in.normal);
        float3 toEye = normalize(u.eyeHalf.xyz - in.world);
        float rim = 1.0 - abs(dot(n, toEye));
        return float4(float3(0.80, 0.84, 0.90), 0.035 + rim * 0.05);
    }

    // Nozzle: a small mesh (position, normal, colour, emissive) placed at the live position.
    struct NozzleVertex { float px, py, pz, nx, ny, nz, r, g, b, emissive; };
    struct NozzleOut { float4 position [[position]]; float3 world; float3 normal; float3 color; float emissive; };

    vertex NozzleOut nozzleVertex(uint vid [[vertex_id]], const device NozzleVertex* vertices [[buffer(0)]],
                                  constant Uniforms& u [[buffer(1)]]) {
        NozzleVertex v = vertices[vid];
        NozzleOut out;
        out.world = float3(v.px, v.py, v.pz) + u.live.yzw + float3(0, 0, 0.05);
        out.position = u.viewProj * float4(out.world, 1);
        out.normal = float3(v.nx, v.ny, v.nz);
        out.color = float3(v.r, v.g, v.b);
        out.emissive = v.emissive;
        return out;
    }

    fragment float4 nozzleFragment(NozzleOut in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
        if (in.emissive > 0.5) { return float4(in.color, 1); }
        float3 n = normalize(in.normal);
        float3 toEye = normalize(u.eyeHalf.xyz - in.world);
        float3 sun = normalize(float3(-0.35, -0.55, 0.75));
        float diffuse = 0.55 * max(dot(n, sun), 0.0) + 0.30 * abs(dot(n, toEye));
        float3 halfway = normalize(sun + toEye);
        float specular = pow(max(dot(n, halfway), 0.0), 24.0) * 0.45;
        return float4(in.color * (0.30 + diffuse) + specular, 1);
    }

    struct BedOut { float4 position [[position]]; float2 world; };

    vertex BedOut bedVertex(uint vid [[vertex_id]], constant Uniforms& u [[buffer(1)]]) {
        float2 corners[4] = { u.bed.xy, float2(u.bed.z, u.bed.y), float2(u.bed.x, u.bed.w), u.bed.zw };
        BedOut out;
        out.world = corners[vid];
        out.position = u.viewProj * float4(out.world, -0.02, 1);
        return out;
    }

    fragment float4 bedFragment(BedOut in [[stage_in]]) {
        float3 base = float3(0.165, 0.180, 0.200);
        float2 cell10 = abs(fract(in.world / 10.0 - 0.5) - 0.5) / fwidth(in.world / 10.0);
        float2 cell50 = abs(fract(in.world / 50.0 - 0.5) - 0.5) / fwidth(in.world / 50.0);
        float minor = 1.0 - min(min(cell10.x, cell10.y), 1.0);
        float major = 1.0 - min(min(cell50.x, cell50.y), 1.0);
        float3 color = base + minor * 0.035 + major * 0.07;
        return float4(color, 1);
    }
    """
}

/// A simple hot-end, modelled in millimetres with the nozzle tip at the origin: glowing tip, brass nozzle and hex,
/// aluminium heater block, steel heat break and a finned heatsink.
enum NozzleMesh {
    static func make() -> [Float] {
        var out: [Float] = []
        func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ c: SIMD3<Float>, _ emissive: Float = 0) {
            out += [p.x, p.y, p.z, n.x, n.y, n.z, c.x, c.y, c.z, emissive]
        }
        func rgb(_ hex: UInt32) -> SIMD3<Float> {
            SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
        }
        /// A (possibly tapered) cylinder with caps, centred on (cx, cy).
        func cylinder(_ r0: Float, _ r1: Float, _ z0: Float, _ z1: Float, sides: Int, _ color: SIMD3<Float>,
                      cx: Float = 0, cy: Float = 0, emissive: Float = 0) {
            for i in 0..<sides {
                let a0 = Float(i) / Float(sides) * 2 * .pi, a1 = Float(i + 1) / Float(sides) * 2 * .pi
                let d0 = SIMD2(cos(a0), sin(a0)), d1 = SIMD2(cos(a1), sin(a1))
                let p00 = SIMD3(cx + d0.x * r0, cy + d0.y * r0, z0), p01 = SIMD3(cx + d1.x * r0, cy + d1.y * r0, z0)
                let p10 = SIMD3(cx + d0.x * r1, cy + d0.y * r1, z1), p11 = SIMD3(cx + d1.x * r1, cy + d1.y * r1, z1)
                let slope = (r0 - r1) / max(0.001, z1 - z0)
                let n0 = simd_normalize(SIMD3(d0.x, d0.y, slope)), n1 = simd_normalize(SIMD3(d1.x, d1.y, slope))
                vertex(p00, n0, color, emissive); vertex(p01, n1, color, emissive); vertex(p10, n0, color, emissive)
                vertex(p10, n0, color, emissive); vertex(p01, n1, color, emissive); vertex(p11, n1, color, emissive)
                vertex(SIMD3(cx, cy, z1), SIMD3(0, 0, 1), color, emissive); vertex(p10, SIMD3(0, 0, 1), color, emissive); vertex(p11, SIMD3(0, 0, 1), color, emissive)
                vertex(SIMD3(cx, cy, z0), SIMD3(0, 0, -1), color, emissive); vertex(p01, SIMD3(0, 0, -1), color, emissive); vertex(p00, SIMD3(0, 0, -1), color, emissive)
            }
        }
        func box(_ minP: SIMD3<Float>, _ maxP: SIMD3<Float>, _ color: SIMD3<Float>) {
            let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
                (SIMD3(0, 0, 1), [SIMD3(minP.x, minP.y, maxP.z), SIMD3(maxP.x, minP.y, maxP.z), SIMD3(maxP.x, maxP.y, maxP.z), SIMD3(minP.x, maxP.y, maxP.z)]),
                (SIMD3(0, 0, -1), [SIMD3(minP.x, minP.y, minP.z), SIMD3(minP.x, maxP.y, minP.z), SIMD3(maxP.x, maxP.y, minP.z), SIMD3(maxP.x, minP.y, minP.z)]),
                (SIMD3(1, 0, 0), [SIMD3(maxP.x, minP.y, minP.z), SIMD3(maxP.x, maxP.y, minP.z), SIMD3(maxP.x, maxP.y, maxP.z), SIMD3(maxP.x, minP.y, maxP.z)]),
                (SIMD3(-1, 0, 0), [SIMD3(minP.x, minP.y, minP.z), SIMD3(minP.x, minP.y, maxP.z), SIMD3(minP.x, maxP.y, maxP.z), SIMD3(minP.x, maxP.y, minP.z)]),
                (SIMD3(0, 1, 0), [SIMD3(minP.x, maxP.y, minP.z), SIMD3(minP.x, maxP.y, maxP.z), SIMD3(maxP.x, maxP.y, maxP.z), SIMD3(maxP.x, maxP.y, minP.z)]),
                (SIMD3(0, -1, 0), [SIMD3(minP.x, minP.y, minP.z), SIMD3(maxP.x, minP.y, minP.z), SIMD3(maxP.x, minP.y, maxP.z), SIMD3(minP.x, minP.y, maxP.z)]),
            ]
            for (n, q) in faces {
                vertex(q[0], n, color); vertex(q[1], n, color); vertex(q[2], n, color)
                vertex(q[0], n, color); vertex(q[2], n, color); vertex(q[3], n, color)
            }
        }

        let brass = rgb(0xD4A94A), aluminium = rgb(0xB9BFC7), steel = rgb(0x8C939C), heatsink = rgb(0x3C424C)
        cylinder(0.75, 0.75, 0.0, 0.5, sides: 16, SIMD3(1.0, 0.58, 0.18), emissive: 1)  // hot tip
        cylinder(0.6, 3.0, 0.4, 4.2, sides: 24, brass)                                    // nozzle cone
        cylinder(4.0, 4.0, 4.2, 7.0, sides: 6, brass)                                     // hex
        box(SIMD3(-11, -6, 7), SIMD3(5, 6, 18), aluminium)                                // heater block
        cylinder(1.6, 1.6, 18, 22, sides: 16, steel)                                      // heat break
        for fin in 0..<7 {                                                                // heatsink fins
            let z = 22 + Float(fin) * 2.6
            cylinder(8.5, 8.5, z, z + 1.2, sides: 24, heatsink)
        }
        cylinder(4.5, 4.5, 22, 40, sides: 20, heatsink)                                   // heatsink core
        return out
    }
}
