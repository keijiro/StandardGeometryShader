// Standard geometry shader example
// https://github.com/keijiro/StandardGeometryShader

#include "UnityCG.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardUtils.cginc"

// Cube map shadow caster; Used to render point light shadows on platforms
// that lacks depth cube map support.
#if defined(SHADOWS_CUBE) && !defined(SHADOWS_CUBE_IN_DEPTH_TEX)
#define PASS_CUBE_SHADOWCASTER
#endif

// Shader uniforms
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

#if defined(PASS_CUBE_SHADOWCASTER)
    // Cube map shadow caster pass
    float3 shadow : TEXCOORD0;

#elif defined(UNITY_PASS_SHADOWCASTER)
    // Default shadow caster pass

#else
    // GBuffer construction pass
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
    // Only do object space to world space transform.
    input.position = mul(unity_ObjectToWorld, input.position);
    input.normal = UnityObjectToWorldNormal(input.normal);
    input.tangent.xyz = UnityObjectToWorldDir(input.tangent.xyz);
    input.texcoord = TRANSFORM_TEX(input.texcoord, _MainTex);
    return input;
}

//
// Geometry stage
//

Varyings VertexOutput(float3 wpos, half3 wnrm, half4 wtan, float2 uv)
{
    Varyings o;

#if defined(PASS_CUBE_SHADOWCASTER)
    // Cube map shadow caster pass: Transfer the shadow vector.
    o.position = UnityWorldToClipPos(float4(wpos, 1));
    o.shadow = wpos - _LightPositionRange.xyz;

#elif defined(UNITY_PASS_SHADOWCASTER)
    // Default shadow caster pass: Apply the shadow bias.
    float scos = dot(wnrm, normalize(UnityWorldSpaceLightDir(wpos)));
    wpos -= wnrm * unity_LightShadowBias.z * sqrt(1 - scos * scos);
    o.position = UnityApplyLinearShadowBias(UnityWorldToClipPos(float4(wpos, 1)));

#else
    // GBuffer construction pass
    half3 bi = cross(wnrm, wtan) * wtan.w * unity_WorldTransformParams.w;
    o.position = UnityWorldToClipPos(float4(wpos, 1));
    o.normal = wnrm;
    o.texcoord = uv;
    o.tspace0 = float4(wtan.x, bi.x, wnrm.x, wpos.x);
    o.tspace1 = float4(wtan.y, bi.y, wnrm.y, wpos.y);
    o.tspace2 = float4(wtan.z, bi.z, wnrm.z, wpos.z);
    o.ambient = ShadeSHPerVertex(wnrm, 0);

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
    float3 wp0 = input[0].position.xyz;
    float3 wp1 = input[1].position.xyz;
    float3 wp2 = input[2].position.xyz;

    float2 uv0 = input[0].texcoord;
    float2 uv1 = input[1].texcoord;
    float2 uv2 = input[2].texcoord;

    // Extrusion amount
    float ext = saturate(0.4 - cos(_LocalTime * UNITY_PI * 2) * 0.41);
    ext *= 1 + 0.3 * sin(pid * 832.37843 + _LocalTime * 88.76);

    // Extrusion points
    float3 offs = ConstructNormal(wp0, wp1, wp2) * ext;
    float3 wp3 = wp0 + offs;
    float3 wp4 = wp1 + offs;
    float3 wp5 = wp2 + offs;

    // Cap triangle
    float3 wn = ConstructNormal(wp3, wp4, wp5);
    float np = saturate(ext * 10);
    float3 wn0 = lerp(input[0].normal, wn, np);
    float3 wn1 = lerp(input[1].normal, wn, np);
    float3 wn2 = lerp(input[2].normal, wn, np);
    outStream.Append(VertexOutput(wp3, wn0, input[0].tangent, uv0));
    outStream.Append(VertexOutput(wp4, wn1, input[1].tangent, uv1));
    outStream.Append(VertexOutput(wp5, wn2, input[2].tangent, uv2));
    outStream.RestartStrip();

    // Side faces
    float4 wt = float4(normalize(wp3 - wp0), 1); // world space tangent
    wn = ConstructNormal(wp3, wp0, wp4);
    outStream.Append(VertexOutput(wp3, wn, wt, uv0));
    outStream.Append(VertexOutput(wp0, wn, wt, uv0));
    outStream.Append(VertexOutput(wp4, wn, wt, uv1));
    outStream.Append(VertexOutput(wp1, wn, wt, uv1));
    outStream.RestartStrip();

    wn = ConstructNormal(wp4, wp1, wp5);
    outStream.Append(VertexOutput(wp4, wn, wt, uv1));
    outStream.Append(VertexOutput(wp1, wn, wt, uv1));
    outStream.Append(VertexOutput(wp5, wn, wt, uv2));
    outStream.Append(VertexOutput(wp2, wn, wt, uv2));
    outStream.RestartStrip();

    wn = ConstructNormal(wp5, wp2, wp3);
    outStream.Append(VertexOutput(wp5, wn, wt, uv2));
    outStream.Append(VertexOutput(wp2, wn, wt, uv2));
    outStream.Append(VertexOutput(wp3, wn, wt, uv0));
    outStream.Append(VertexOutput(wp0, wn, wt, uv0));
    outStream.RestartStrip();
}

//
// Fragment phase
//

#if defined(PASS_CUBE_SHADOWCASTER)

// Cube map shadow caster pass
half4 Fragment(Varyings input) : SV_Target
{
    float depth = length(input.shadow) + unity_LightShadowBias.x;
    return UnityEncodeCubeShadowDepth(depth * _LightPositionRange.w);
}

#elif defined(UNITY_PASS_SHADOWCASTER)

// Default shadow caster pass
half4 Fragment() : SV_Target { return 0; }

#else

// GBuffer construction pass
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

    // Tangent space conversion (tangent space normal -> world space normal)
    float3 wn = normalize(float3(
        dot(input.tspace0.xyz, normal),
        dot(input.tspace1.xyz, normal),
        dot(input.tspace2.xyz, normal)
    ));

    // Update the GBuffer.
    UnityStandardData data;
    data.diffuseColor = c_diff;
    data.occlusion = occ;
    data.specularColor = c_spec;
    data.smoothness = _Glossiness;
    data.normalWorld = wn;
    UnityStandardDataToGbuffer(data, outGBuffer0, outGBuffer1, outGBuffer2);

    // Calculate ambient lighting and output to the emission buffer.
    float3 wp = float3(input.tspace0.w, input.tspace1.w, input.tspace2.w);
    half3 sh = ShadeSHPerPixel(data.normalWorld, input.ambient, wp);
    outEmission = half4(sh * c_diff, 1) * occ;
}

#endif
