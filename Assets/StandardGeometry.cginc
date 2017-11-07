#include "UnityCG.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardUtils.cginc"

// Cube map shadow caster; Used to render point light shadows on platforms
// without depth cube map support.
#if defined(SHADOWS_CUBE) && !defined(SHADOWS_CUBE_IN_DEPTH_TEX)
#define STDGEO_SHADOW_CASTER_CUBE
#endif

// Shader properties
half4 _Color;
sampler2D _MainTex;
float4 _MainTex_ST;

half _Glossiness;
half _Metallic;

sampler2D _BumpMap;
float _BumpScale;

sampler2D _OcclusionMap;
float _OcclusionStrength;

float _LocalTime;

// Vertex input attributes
struct Attributes
{
    float4 position : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
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
    float4 tspace0 : TEXCOORD1;
    float4 tspace1 : TEXCOORD2;
    float4 tspace2 : TEXCOORD3;
    half3 ambient : TEXCOORD4;

#endif
};

//
// Vertex stage
//

Attributes Vertex(Attributes input)
{
    input.position = mul(unity_ObjectToWorld, input.position);
    input.normal = UnityObjectToWorldNormal(input.normal);
    input.tangent.xyz = UnityObjectToWorldDir(input.tangent.xyz);
    input.texcoord = TRANSFORM_TEX(input.texcoord, _MainTex);
    return input;
}

//
// Geometry stage
//

Varyings GeoOutWPosNrm(float3 wp, half3 wn, half4 wt, float2 uv)
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
    half3 wb = cross(wn, wt) * wt.w * unity_WorldTransformParams.w;
    o.position = UnityWorldToClipPos(float4(wp, 1));
    o.normal = wn;
    o.texcoord = uv;
    o.tspace0 = float4(wt.x, wb.x, wn.x, wp.x);
    o.tspace1 = float4(wt.y, wb.y, wn.y, wp.y);
    o.tspace2 = float4(wt.z, wb.z, wn.z, wp.z);
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
    float3 n0 = lerp(input[0].normal, n, np);
    float3 n1 = lerp(input[1].normal, n, np);
    float3 n2 = lerp(input[2].normal, n, np);
    outStream.Append(GeoOutWPosNrm(p3, n0, input[0].tangent, uv0));
    outStream.Append(GeoOutWPosNrm(p4, n1, input[1].tangent, uv1));
    outStream.Append(GeoOutWPosNrm(p5, n2, input[2].tangent, uv2));
    outStream.RestartStrip();

    // Side faces
    n = ConstructNormal(p3, p0, p4);
    float4 t = float4(normalize(p3 - p0), 1);
    outStream.Append(GeoOutWPosNrm(p3, n, t, uv0));
    outStream.Append(GeoOutWPosNrm(p0, n, t, uv0));
    outStream.Append(GeoOutWPosNrm(p4, n, t, uv1));
    outStream.Append(GeoOutWPosNrm(p1, n, t, uv1));
    outStream.RestartStrip();

    n = ConstructNormal(p4, p1, p5);
    outStream.Append(GeoOutWPosNrm(p4, n, t, uv1));
    outStream.Append(GeoOutWPosNrm(p1, n, t, uv1));
    outStream.Append(GeoOutWPosNrm(p5, n, t, uv2));
    outStream.Append(GeoOutWPosNrm(p2, n, t, uv2));
    outStream.RestartStrip();

    n = ConstructNormal(p5, p2, p3);
    outStream.Append(GeoOutWPosNrm(p5, n, t, uv2));
    outStream.Append(GeoOutWPosNrm(p2, n, t, uv2));
    outStream.Append(GeoOutWPosNrm(p3, n, t, uv0));
    outStream.Append(GeoOutWPosNrm(p0, n, t, uv0));
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

    half4 normal = tex2D(_BumpMap, input.texcoord);
    normal.xyz = UnpackScaleNormal(normal, _BumpScale);

    half occ = tex2D(_OcclusionMap, input.texcoord).g;
    occ = LerpOneTo(occ, _OcclusionStrength);

    // PBS workflow conversion (metallic -> specular)
    half3 c_diff, c_spec;
    half refl10;
    c_diff = DiffuseAndSpecularFromMetallic(
        albedo, _Metallic, // input
        c_spec, refl10     // output
    );

    // Tangent space normal -> world space normal
    float3 wn = normalize(float3(
        dot(input.tspace0.xyz, normal),
        dot(input.tspace1.xyz, normal),
        dot(input.tspace2.xyz, normal)
    ));

    // Output to GBuffers.
    UnityStandardData data;
    data.diffuseColor = c_diff;
    data.occlusion = occ;
    data.specularColor = c_spec;
    data.smoothness = _Glossiness;
    data.normalWorld = wn;
    UnityStandardDataToGbuffer(data, outGBuffer0, outGBuffer1, outGBuffer2);

    // Ambient lighting -> emission buffer
    float3 wpos = float3(input.tspace0.w, input.tspace1.w, input.tspace2.w);
    half3 sh = ShadeSHPerPixel(data.normalWorld, input.ambient, wpos);
    outEmission = half4(sh * c_diff, 1) * occ;
}

#endif
