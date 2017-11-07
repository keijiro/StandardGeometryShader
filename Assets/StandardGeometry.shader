Shader "Standard Geometry Test"
{
    Properties
    {
        _Color("Color", Color) = (1, 1, 1, 1)
        _MainTex("Albedo", 2D) = "white" {}
        _Glossiness("Smoothness", Range(0, 1)) = 0.5
        _Metallic("Metallic", Range(0, 1)) = 0.0
        _LocalTime("Animation Time", Float) = 0.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            Tags { "LightMode"="Deferred" }
            CGPROGRAM
            #pragma vertex Vertex
            #pragma geometry Geometry
            #pragma fragment Fragment
            #include "StandardGeometry.cginc"
            ENDCG
        }
        Pass
        {
            Tags { "LightMode"="ShadowCaster" }
            CGPROGRAM
            #pragma vertex Vertex
            #pragma geometry Geometry
            #pragma fragment Fragment
            #pragma multi_compile_shadowcaster
            #define STDGEO_SHADOW_CASTER
            #include "StandardGeometry.cginc"
            ENDCG
        }
    }
    FallBack "Diffuse"
}
