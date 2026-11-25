/// Shaders de Metal. Se compilan en tiempo de ejecución desde texto para no depender
/// de cómo empaqueta Xcode los .metal dentro de un Swift Package.
enum ShaderSource {
    static let code = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal   [[attribute(1)]];
    };

    struct Uniforms {
        float4x4 viewProjection;
        float4x4 model;
        float4 baseColor;
        float4 lightDir;
    };

    struct VertexOut {
        float4 position [[position]];
        float3 normal;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                 constant Uniforms &u [[buffer(1)]]) {
        VertexOut out;
        float4 world = u.model * float4(in.position, 1.0);
        out.position = u.viewProjection * world;
        out.normal = (u.model * float4(in.normal, 0.0)).xyz;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  bool frontFacing [[front_facing]],
                                  constant Uniforms &u [[buffer(1)]]) {
        float3 n = normalize(in.normal);
        float3 l = normalize(u.lightDir.xyz);
        float diffuse = abs(dot(n, l));
        float rim = pow(1.0 - diffuse, 3.0) * 0.25;
        float3 color = u.baseColor.rgb * (0.22 + 0.78 * diffuse) + rim;
        // Caras traseras visibles en rojizo: ayuda a detectar normales invertidas.
        if (!frontFacing) {
            color = mix(color, float3(0.85, 0.25, 0.25), 0.6);
        }
        return float4(color, 1.0);
    }
    """
}
