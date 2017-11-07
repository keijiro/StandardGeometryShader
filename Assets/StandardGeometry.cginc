#include "UnityCG.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardUtils.cginc"

// Cube map shadow caster; Used to render point light shadows on platforms
// without depth cube map support.
#if defined(SHADOWS_CUBE) && !defined(SHADOWS_CUBE_IN_DEPTH_TEX)
#define STDGEO_SHADOW_CASTER_CUBE
#endif

// Shader properties
sampler2D _MainTex;
float4 _MainTex_ST;
half _Glossiness;
half _Metallic;
half4 _Color;
float _LocalTime;

// Vertex input attributes
struct Attributes
{
    float4 position : POSITION;
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD;
};

// Fragment varyings
struct Varyings
{
    float4 position : SV_POSITION;

#if defined(STDGEO_SHADOW_CASTER_CUBE)
    // Cube map shadow caster
    float3 shadow : TEXCOORD0;

#elif defined(STDGEO_SHADOW_CASTER)
    // Default shadow caster

#else
    // GBuffer constructor
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
    float3 worldPos : TEXCOORD1;
    half3 ambient : TEXCOORD2;

#endif
};

//
// Vertex stage
//

Attributes Vertex(Attributes input)
{
    input.position = mul(unity_ObjectToWorld, input.position);
    input.normal = UnityObjectToWorldNormal(input.normal);
    input.texcoord = TRANSFORM_TEX(input.texcoord, _MainTex);
    return input;
}

//
// Geometry stage
//

Varyings GeoOutWPosNrm(float3 wp, half3 wn, float2 uv)
{
    Varyings o;

#if defined(STDGEO_SHADOW_CASTER_CUBE)
    // Cube map shadow caster: Transfer the shadow vector.
    o.position = UnityWorldToClipPos(float4(wp, 1));
    o.shadow = wp - _LightPositionRange.xyz;

#elif defined(STDGEO_SHADOW_CASTER)
    // Default shadow caster: Apply the shadow bias.
    float scos = dot(wn, normalize(UnityWorldSpaceLightDir(wp)));
    wp -= wn * unity_LightShadowBias.z * sqrt(1 - scos * scos);
    o.position = UnityApplyLinearShadowBias(UnityWorldToClipPos(float4(wp, 1)));

#else
    // GBuffer constructor
    o.position = UnityWorldToClipPos(float4(wp, 1));
    o.normal = wn;
    o.texcoord = uv;
    o.worldPos = wp;
    o.ambient = ShadeSHPerVertex(wn, 0);

#endif

    return o;
}

float3 ConstructNormal(float3 v1, float3 v2, float3 v3)
{
    return normalize(cross(v2 - v1, v3 - v1));
}

[maxvertexcount(15)]
void Geometry(
    triangle Attributes input[3], uint pid : SV_PrimitiveID,
    inout TriangleStream<Varyings> outStream
)
{
    // Vertex inputs
    float3 p0 = input[0].position.xyz;
    float3 p1 = input[1].position.xyz;
    float3 p2 = input[2].position.xyz;

    float3 n0 = input[0].normal;
    float3 n1 = input[1].normal;
    float3 n2 = input[2].normal;

    float2 uv0 = input[0].texcoord;
    float2 uv1 = input[1].texcoord;
    float2 uv2 = input[2].texcoord;

    // Extrusion amount
    float ext = saturate(0.4 - cos(_LocalTime * UNITY_PI * 2) * 0.41);
    ext *= 1 + 0.3 * sin(pid * 832.37843 + _LocalTime * 88.76);

    // Extrusion points
    float3 offs = ConstructNormal(p0, p1, p2) * ext;
    float3 p3 = p0 + offs;
    float3 p4 = p1 + offs;
    float3 p5 = p2 + offs;

    // Cap triangle
    float3 n = ConstructNormal(p3, p4, p5);
    float np = saturate(ext * 10);
    outStream.Append(GeoOutWPosNrm(p3, lerp(n0, n, np), uv0));
    outStream.Append(GeoOutWPosNrm(p4, lerp(n1, n, np), uv1));
    outStream.Append(GeoOutWPosNrm(p5, lerp(n2, n, np), uv2));
    outStream.RestartStrip();

    // Side faces
    n = ConstructNormal(p3, p0, p4);
    outStream.Append(GeoOutWPosNrm(p3, n, uv0));
    outStream.Append(GeoOutWPosNrm(p0, n, uv0));
    outStream.Append(GeoOutWPosNrm(p4, n, uv1));
    outStream.Append(GeoOutWPosNrm(p1, n, uv1));
    outStream.RestartStrip();

    n = ConstructNormal(p4, p1, p5);
    outStream.Append(GeoOutWPosNrm(p4, n, uv1));
    outStream.Append(GeoOutWPosNrm(p1, n, uv1));
    outStream.Append(GeoOutWPosNrm(p5, n, uv2));
    outStream.Append(GeoOutWPosNrm(p2, n, uv2));
    outStream.RestartStrip();

    n = ConstructNormal(p5, p2, p3);
    outStream.Append(GeoOutWPosNrm(p5, n, uv2));
    outStream.Append(GeoOutWPosNrm(p2, n, uv2));
    outStream.Append(GeoOutWPosNrm(p3, n, uv0));
    outStream.Append(GeoOutWPosNrm(p0, n, uv0));
    outStream.RestartStrip();
}

//
// Fragment phase
//

#if defined(STDGEO_SHADOW_CASTER_CUBE)

// Cube map shadow caster
half4 Fragment(Varyings input) : SV_Target
{
    float depth = length(input.shadow) + unity_LightShadowBias.x;
    return UnityEncodeCubeShadowDepth(depth * _LightPositionRange.w);
}

#elif defined(STDGEO_SHADOW_CASTER)

// Default shadow caster
half4 Fragment() : SV_Target { return 0; }

#else

// GBuffer constructor
void Fragment(
    Varyings input,
    out half4 outGBuffer0 : SV_Target0,
    out half4 outGBuffer1 : SV_Target1,
    out half4 outGBuffer2 : SV_Target2,
    out half4 outEmission : SV_Target3
)
{
    // Sample textures
    half3 albedo = tex2D(_MainTex, input.texcoord).rgb * _Color.rgb;

    // PBS workflow conversion (metallic -> specular)
    half3 c_diff, c_spec;
    half refl10;
    c_diff = DiffuseAndSpecularFromMetallic(
        albedo, _Metallic, // input
        c_spec, refl10     // output
    );

    // Output to GBuffers.
    UnityStandardData data;
    data.diffuseColor = c_diff;
    data.occlusion = 1;
    data.specularColor = c_spec;
    data.smoothness = _Glossiness;
    data.normalWorld = normalize(input.normal);
    UnityStandardDataToGbuffer(data, outGBuffer0, outGBuffer1, outGBuffer2);

    // Ambient lighting -> emission buffer
    half3 sh = ShadeSHPerPixel(data.normalWorld, input.ambient, input.worldPos);
    outEmission = half4(sh * c_diff, 1);
}

#endif
