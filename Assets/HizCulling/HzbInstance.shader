Shader "Unlit/HizInstancing"
{
	Properties
	{
		_MainTex("Base Map",2D) = "white"{}
		_WindNoiseTexture("WindNoise Map",2D) = "white"{}
		_WindStrength("WindStrength", Range(0.0,10.0)) = 0.5
		_WindPeriod("WindPeriod",Vector) = (0,0,0,0)
		_WindPositionScale("WindPositionScale",Range(0.0,10.0)) = 1
		_Cutoff("Cull Off", Range(0.0, 1.0)) = 0.5
		_Metallic("Metallic",Range(0.0,1.0)) = 0.5
		_Smoothness("Smoothness",Range(0.0,1.0)) = 0.5
	}
	SubShader{
	
		Tags{
		"RenderType" = "Opaque"
		"RenderPipeline" = "UniversalPipeline"
		"ShaderModel"="4.5"
		}



		LOD 100

		HLSLINCLUDE

		#if SHADER_TARGET >= 45
			StructuredBuffer<float4x4> visPositionBuffer;
			StructuredBuffer<float4x4> AllPositionBuffer;
		#endif
			half _WindPositionScale;
			half _WindStrength;
			sampler2D _WindNoiseTexture;
			half4 _WindPeriod;
		void rotate2D(inout float2 v, float r)
            {
                float s, c;
                sincos(r, s, c);
                v = float2(v.x * c - v.y * s, v.x * s + v.y * c);
            }
		struct WindStruct 
		{
			half time;
			half windPositionScale;
			half windStrength;
			half UV_V_Mask;
			float2 period;
			float4 posWS;
		};
		float4 WindVertexAnimationLocalOffest(WindStruct windStruct,sampler2D windNoise)
		{
			WindStruct wd = windStruct;
			float2 windPeriod = wd.time* wd.period.xy;
			float2 uvWS =  wd.posWS.xz * wd.windPositionScale+windPeriod;
			float4 noise = tex2Dlod(windNoise, float4(uvWS,0,0.0));
			noise = (noise*2- 1);

			return noise* wd.UV_V_Mask*wd.windStrength;
			
			//return float4(0, 0, 0, 0);
		}
		float3 RotateAroundAxis( float3 center, float3 original, float3 u, float angle )
		{
			original -= center;
			float C = cos( angle );
			float S = sin( angle );
			float t = 1 - C;
			float m00 = t * u.x * u.x + C;
			float m01 = t * u.x * u.y - S * u.z;
			float m02 = t * u.x * u.z + S * u.y;
			float m10 = t * u.x * u.y + S * u.z;
			float m11 = t * u.y * u.y + C;
			float m12 = t * u.y * u.z - S * u.x;
			float m20 = t * u.x * u.z - S * u.y;
			float m21 = t * u.y * u.z + S * u.x;
			float m22 = t * u.z * u.z + C;
			float3x3 finalMatrix = float3x3( m00, m01, m02, m10, m11, m12, m20, m21, m22 );
			return mul( finalMatrix, original ) + center;
		}
		#pragma shader_feature_local _MAIN_LIGHT_SHADOWS_CASCADE_CC
		ENDHLSL


		pass
		{
			Cull Off
			ZWrite On

			Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}
			HLSLPROGRAM
			#pragma exclude_renderers gles gles3 glcore
			#pragma target 4.5
			#pragma vertex vert
			#pragma fragment frag
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON

            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			TEXTURE2D(_MainTex);
			SAMPLER(sampler_MainTex);
			float4 _MainTex_ST;
			float3 _LightDirection;
			//half _Cutoff;

			// Computes the specular term for EnvironmentBRDF
			half3 EnvironmentBRDFSpecularCC(half3 diffuse,half3 indirectSpecular,half3 indirectDiffuse, half specular,half grazingTerm,half roughness2, half fresnelTerm)
			{
				
				//return diffuse;
				
				float surfaceReduction = 1.0 / (roughness2 + 1.0);
				half3 result = half3(0, 0, 0);
				//result = indirectDiffuse * diffuse;
				result += diffuse;
				result += indirectSpecular * surfaceReduction * lerp(specular, grazingTerm, fresnelTerm);
				return result;
				
			}

			//half3 EnvironmentBRDF(BRDFData brdfData, half3 indirectDiffuse, half3 indirectSpecular, half fresnelTerm)
			//{
			//	half3 c = indirectDiffuse * brdfData.diffuse;
			//	c += indirectSpecular * EnvironmentBRDFSpecular(brdfData, fresnelTerm);
			//	return c;
			//}


			// Computes the scalar specular term for Minimalist CookTorrance BRDF
			// NOTE: needs to be multiplied with reflectance f0, i.e. specular color to complete
			half DirectBRDFSpecular(half roughness2, half roughness2MinusOne, half3 normalWS, half3 lightDirectionWS, half3 viewDirectionWS,half normalizationTerm)
			{
				float3 halfDir = SafeNormalize(float3(lightDirectionWS)+float3(viewDirectionWS));

				float NoH = saturate(dot(normalWS, halfDir));
				half LoH = saturate(dot(lightDirectionWS, halfDir));

				// GGX Distribution multiplied by combined approximation of Visibility and Fresnel
				// BRDFspec = (D * V * F) / 4.0
				// D = roughness^2 / ( NoH^2 * (roughness^2 - 1) + 1 )^2
				// V * F = 1.0 / ( LoH^2 * (roughness + 0.5) )
				// See "Optimizing PBR for Mobile" from Siggraph 2015 moving mobile graphics course
				// https://community.arm.com/events/1155

				// Final BRDFspec = roughness^2 / ( NoH^2 * (roughness^2 - 1) + 1 )^2 * (LoH^2 * (roughness + 0.5) * 4.0)
				// We further optimize a few light invariant terms
				// brdfData.normalizationTerm = (roughness + 0.5) * 4.0 rewritten as roughness * 4.0 + 2.0 to a fit a MAD.
				float d = NoH * NoH * roughness2MinusOne + 1.00001f;

				half LoH2 = LoH * LoH;
				half specularTerm = roughness2 / ((d * d) * max(0.1h, LoH2) * normalizationTerm);

				// On platforms where half actually means something, the denominator has a risk of overflow
				// clamp below was added specifically to "fix" that, but dx compiler (we convert bytecode to metal/gles)
				// sees that specularTerm have only non-negative terms, so it skips max(0,..) in clamp (leaving only min(100,...))
#if defined (SHADER_API_MOBILE) || defined (SHADER_API_SWITCH)
				specularTerm = specularTerm - HALF_MIN;
				specularTerm = clamp(specularTerm, 0.0, 100.0); // Prevent FP16 overflow on mobiles
#endif

				return specularTerm;
			}
			struct Attributes
			{
				float4 posOS :POSITION;
				float2 uv : TEXCOORD0;
				float4 normal:NORMAL;
				UNITY_VERTEX_INPUT_INSTANCE_ID
				float2 lightuv:TEXCOORD1;
			};

			struct Varyings
			{
				float2 uv : TEXCOORD0;
				float4 posCS:SV_POSITION;
				UNITY_VERTEX_INPUT_INSTANCE_ID
				UNITY_VERTEX_OUTPUT_STEREO
				float4 Debug : COLOR;
				float4 shadowCoord : TEXCOORD2;
				float4 posWS:TEXCOORD3;
				float3 normalWS:TEXCOORD4;
			    float4 lightmapUVOrVertexSH:TEXCOORD1;
				float fogCoord : TEXCOORD5;
			};



			
			//float4 TransformWorldToShadowCoordCustom(float3 positionWS)
			//{
			//#ifdef _MAIN_LIGHT_SHADOWS_CASCADE
			//	half cascadeIndex = ComputeCascadeIndex(positionWS);
			//#else
			//	half cascadeIndex = 0;
			//#endif

			//	float4 shadowCoord = mul(_MainLightWorldToShadow[cascadeIndex], float4(positionWS, 1.0));

			//	return float4(shadowCoord.xyz, cascadeIndex);
			//}

			//half MainLightRealtimeShadow(float4 shadowCoord)
			//{
			//#if !defined(MAIN_LIGHT_CALCULATE_SHADOWS)
			//	return 1.0h;
			//#elif defined(_MAIN_LIGHT_SHADOWS_SCREEN)
			//	return SampleScreenSpaceShadowmap(shadowCoord);
			//#else
			//	ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
			//	half4 shadowParams = GetMainLightShadowParams();
			//	return SampleShadowmap(TEXTURE2D_ARGS(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture), shadowCoord, shadowSamplingData, shadowParams, false);
			//#endif
			//}

			half MainLightRealtimeShadowCC(float4 shadowCoord)
			{
//#if !defined(MAIN_LIGHT_CALCULATE_SHADOWS)
				//return 1.0h;
				
//#elif defined(_MAIN_LIGHT_SHADOWS_SCREEN)
				//return SampleScreenSpaceShadowmap(shadowCoord);
//#else
				ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
				half4 shadowParams = GetMainLightShadowParams();
				return SampleShadowmap(TEXTURE2D_ARGS(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture), shadowCoord, shadowSamplingData, shadowParams, false);
//#endif
			}

			Light GetMainLightCC(float4 shadowCoord)
			{
				Light light = GetMainLight();
				light.shadowAttenuation = MainLightRealtimeShadowCC(shadowCoord);
				return light;
			}
			

			float4 TransformWorldToShadowCoordCC(float3 positionWS)
			{
#if defined(_MAIN_LIGHT_SHADOWS_CASCADE_CC)
				half cascadeIndex = ComputeCascadeIndex(positionWS);
#else
				half cascadeIndex = 0;
#endif

				float4 shadowCoord = mul(_MainLightWorldToShadow[cascadeIndex], float4(positionWS, 1.0));

				return float4(shadowCoord.xyz, cascadeIndex);
			}

			float3 ASEIndirectDiffuse(float2 uvStaticLightmap, float3 normalWS)
			{
#ifdef LIGHTMAP_ON
				return SampleLightmap(uvStaticLightmap, normalWS);
#else
				return SampleSH(normalWS);
#endif
			}


			Varyings vert(Attributes Input)
			{
		
				Varyings Output = (Varyings)0;
				UNITY_SETUP_INSTANCE_ID(Input);
				UNITY_TRANSFER_INSTANCE_ID(Input,Output);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(Output);
				
				

				//#ifdef UNITY_DOTS_INSTANCING_ENABLED
				//#if defined(UNITY_INSTANCING_ENABLED) || defined(UNITY_PROCEDURAL_INSTANCING_ENABLED) || defined(UNITY_DOTS_INSTANCING_ENABLED) 
				//#if defined UNITY_SUPPORT_INSTANCING
				//#ifdef	INSTANCING_ON
				#ifdef UNITY_INSTANCING_ENABLED
				//#ifdef UNITY_ANY_INSTANCING_ENABLED 
				//#ifdef UNITY_PROCEDURAL_INSTANCING_ENABLED
					#if SHADER_TARGET >= 45 
						//uint index = visPositionBuffer[UNITY_GET_INSTANCE_ID(Input)];
						//float4x4 data = AllPositionBuffer[index];
						float4x4 data = visPositionBuffer[UNITY_GET_INSTANCE_ID(Input)];
					#else
						float4x4 data = 0;
					#endif
					//float rotation = data.w * data.w * _Time.x * 0.5f;
					//rotate2D(data.xz, rotation);
					//float3 localPosition = RotateAroundAxis(float3(0,0,0), Input.posOS.xyz, float3(0,1,0), 0);
					//float3 localPosition = Input.posOS.xyz;// * data.w;
					float4 worldPosition = float4(0, 0, 0, 1);

					float4 posOS = Input.posOS.xyzw;
					//float4x4 data = {
					//	1.0, 0.0, 0.0, 1.0,
					//	0.0, 1.0, 0.0, 1.0,
					//	0.0, 0.0, 1.0, 1.0,
					//	0.0, 0.0, 0.0, 1.0,
					//};
					worldPosition= mul(data,posOS);
					WindStruct ws = (WindStruct)0;
					//struct WindStruct
					//{
					//	half time;
					//	half windPositionScale;
					//	half windStrength;
					//	float4 period;
					//	float4 posWS;
					//};
					ws.time = _TimeParameters.x;
					ws.windPositionScale = _WindPositionScale;
					ws.period = _WindPeriod;
					ws.posWS = worldPosition;
					ws.windStrength = _WindStrength;
					ws.UV_V_Mask = Input.uv.y;

					worldPosition.xz+= WindVertexAnimationLocalOffest(ws, _WindNoiseTexture).xz;

					Output.shadowCoord = TransformWorldToShadowCoordCC(worldPosition);
					Output.posCS  = mul(UNITY_MATRIX_VP, worldPosition);
					Output.posWS = worldPosition;
					Output.Debug = TransformObjectToWorldNormal(Input.normal).xyzx;
					float3x3 m = {
						1.0,0.0,0.0,
						0.0,1.0,0.0,
						0.0,0.0,1.0,
					};
					float3 rootposWS = float3(data._m03, data._m13, data._m23);
					//Input.normal.w = 1;
					//Output.normalWS = mul(m, Input.normal.xyz);// TransformObjectToWorldNormal(Input.normal);
				
					Output.normalWS =  normalize(worldPosition.xyz - rootposWS.xyz);
					//Output.normalWS = Input.normal;
					OUTPUT_LIGHTMAP_UV(Input.lightuv, unity_LightmapST, Output.lightmapUVOrVertexSH.xy);
					OUTPUT_SH(Output.normalWS, Output.lightmapUVOrVertexSH.xyz);

				#else
					VertexPositionInputs vertexInput = GetVertexPositionInputs(Input.posOS.xyz);
					Output.posCS  = vertexInput.positionCS;
				#endif
				
	
				
				#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
					//Output.shadowCoord = TransformWorldToShadowCoord(worldPosition);
					Output.Debug = float4(0.2,0.6,0.4,1);
				#endif
				Output.uv = TRANSFORM_TEX(Input.uv, _MainTex);
				//Output.fogCoord = ComputeFogFactor(vertexInput.positionCS.z);

				return Output;
			
			
			}

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
				half2 uv = input.uv;
		
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                half3 color = texColor.rgb ;//* _BaseColor.rgb;
                half alpha = texColor.a ;//* _BaseColor.a;
                AlphaDiscard(alpha, _Cutoff);

#ifdef _ALPHAPREMULTIPLY_ON
                color *= alpha;
				
#endif
				

	
				clip(alpha - _Cutoff);
				
				input.shadowCoord = TransformWorldToShadowCoordCC(input.posWS);
				Light mainLight = GetMainLightCC(input.shadowCoord);
				//float lightAtten = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
				float lightAtten = mainLight.shadowAttenuation;
				//color *= (indirectSpecular * indirectDiffuse);
				//half shadow = MainLightRealtimeShadowCC(input.shadowCoord);
				float3 direction = mainLight.direction;
				//float distanceAttenuation = unity_LightData.z; // unity_LightData.z is 1 when not culled by the culling mask, otherwise 0.
				float3 LightColor= mainLight.color;
				
				half NdotL = saturate(dot(input.normalWS.xyz, _MainLightPosition.xyz));
				half3 radiance = lightAtten *LightColor*NdotL;
				
				half metallic = _Metallic;
				half oneMinusReflectivityMetallic = kDielectricSpec.a - kDielectricSpec.a * metallic;
				color *= oneMinusReflectivityMetallic;
				half3 specular = lerp(kDielectricSpec.rgb, color.xyz, metallic);


				half smoothness = _Smoothness;
				half percetualRoughness = 1.0 - smoothness;
				half roughness =max(HALF_MIN_SQRT, percetualRoughness * percetualRoughness);
				half roughness2 = max(roughness * roughness, HALF_MIN);
				half grzingTerm = saturate(smoothness + 1.0 - oneMinusReflectivityMetallic);
				half normalizationTerm = roughness * 4.0h + 2.0h;
				half roughness2MinusOne = roughness2 - 1.0h;

				
			
				float3 worldViewDir = (_WorldSpaceCameraPos.xyz - input.posWS);
				worldViewDir = normalize(worldViewDir);
				half3 reflectVector = reflect(-worldViewDir, input.normalWS);
				half NoV = saturate(dot(input.normalWS, worldViewDir));
				half fresnelTerm = Pow4(1.0 - NoV);


				
				float3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, percetualRoughness, 1.0);
				float3 indirectDiffuse = ASEIndirectDiffuse(input.lightmapUVOrVertexSH, input.normalWS);
				color = EnvironmentBRDFSpecularCC(color, indirectSpecular, indirectDiffuse, specular, grzingTerm, roughness2, fresnelTerm);
				
				half specularTerm = DirectBRDFSpecular(roughness2, roughness2MinusOne, input.normalWS, direction, worldViewDir, normalizationTerm);
				color += specular * specularTerm;
				color *= radiance;
				//color += texColor * indirectDiffuse* LightColor;
				//color += texColor * indirectSpecular* LightColor;

				//return half4(input.Debug.xyz, alpha);
				//return half4(NdotL.xxx, alpha);

				//color = MixFog(color, input.fogCoord);
				return half4(color.xyz, alpha);
				//return half(lightAtten.xxx,alpha);
				//return input.Debug;
				}
			ENDHLSL
		}
		
		pass
		{		
			Name "ShadowCaster"
			Tags{"LightMode" = "ShadowCaster"}

			ZWrite On
			ZTest LEqual
			ColorMask 0
			Cull Off
			HLSLPROGRAM
			#pragma exclude_renderers gles gles3 glcore
			#pragma target 4.5
			#pragma vertex vert
			#pragma fragment frag
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON

            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
			#pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
			#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

			TEXTURE2D(_MainTex);            
			SAMPLER(sampler_MainTex);
			float4 _MainTex_ST;

			struct AttributesC
			{
				float4 posOS :POSITION;
				float2 uv : TEXCOORD0;
				half3  normalOS: NORMAL;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct VaryingsC
			{
				float2 uv : TEXCOORD0;
				float fogCoord: TEXCOORD1;
				float4 posCS:SV_POSITION;
				UNITY_VERTEX_INPUT_INSTANCE_ID
				UNITY_VERTEX_OUTPUT_STEREO
				float4 Debug : COLOR;
			};


			VaryingsC vert(AttributesC Input)
			{
		
				VaryingsC Output = (VaryingsC)0;
				UNITY_SETUP_INSTANCE_ID(Input);
				UNITY_TRANSFER_INSTANCE_ID(Input,Output);

				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(Output);
				
				

				//#ifdef UNITY_DOTS_INSTANCING_ENABLED
				//#if defined(UNITY_INSTANCING_ENABLED) || defined(UNITY_PROCEDURAL_INSTANCING_ENABLED) || defined(UNITY_DOTS_INSTANCING_ENABLED) 
				//#if defined UNITY_SUPPORT_INSTANCING
				//#ifdef	INSTANCING_ON
				#ifdef UNITY_INSTANCING_ENABLED
				//#ifdef UNITY_ANY_INSTANCING_ENABLED 
				//#ifdef UNITY_PROCEDURAL_INSTANCING_ENABLED
					#if SHADER_TARGET >= 45 
						float4x4 data = visPositionBuffer[UNITY_GET_INSTANCE_ID(Input)];
					#else
						float4x4 data = 0;
					#endif
					float4 posOS = Input.posOS;
					float4 worldPosition= mul(data,posOS);
					WindStruct ws = (WindStruct)0;
					//struct WindStruct
					//{
					//	half time;
					//	half windPositionScale;
					//	half windStrength;
					//	float4 period;
					//	float4 posWS;
					//};
					ws.time = _TimeParameters.x;
					ws.windPositionScale = _WindPositionScale;
					ws.period = _WindPeriod;
					ws.posWS = worldPosition;
					ws.windStrength = _WindStrength;
					ws.UV_V_Mask = Input.uv.y;

					worldPosition.xz += WindVertexAnimationLocalOffest(ws, _WindNoiseTexture).xz;

					float3 positionWS = worldPosition;

					float3 normalWS = TransformObjectToWorldNormal(Input.normalOS);
					//float3 normalWS =  normalize(worldPosition.xyz - rootposWS.xyz);
					#if _CASTING_PUNCTUAL_LIGHT_SHADOW
						float3 lightDirectionWS = normalize(_LightPosition - positionWS);
					#else
						float3 lightDirectionWS = _LightDirection;
					#endif
					
					float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

					#if UNITY_REVERSED_Z
						positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
						//positionCS.z = 45;
					#else
						positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
					#endif
					//positionCS.z = 45;
					Output.posCS  = positionCS;
					//Output.posCS  = mul(UNITY_MATRIX_VP, float4(positionWS, 1.0));
					//Output.posOS  = vertexInput.positionCS;
					//Output.Debug = float4(data.w,1,1,1);

				#else
					VertexPositionInputs vertexInput = GetVertexPositionInputs(Input.posOS.xyz);
					Output.posCS  = vertexInput.positionCS;
					Output.Debug = float4(0.2,0.6,0.4,1);
				#endif





				Output.uv = TRANSFORM_TEX(Input.uv, _MainTex);
				//Output.fogCoord = ComputeFogFactor(vertexInput.positionCS.z);

				return Output;
			
			
			}

            half4 frag(VaryingsC input) : SV_Target
            {
                //UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
				half2 uv = input.uv;
		
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                half3 color = texColor.rgb ;//* _BaseColor.rgb;
                half alpha = texColor.a ;//* _BaseColor.a;
//#ifdef _ALPHAPREMULTIPLY_ON
//                color *= alpha;
//#endif

				clip(alpha - _Cutoff);
                //return half4(color, alpha);
				return 0;
				//return input.Debug;
				}
			ENDHLSL
		}
		
		
		/*
		Pass
        {


float4 GetShadowPositionHClip(Attributes input)
{
    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
    float3 lightDirectionWS = _LightDirection;
#endif

    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif

    return positionCS;
}

Varyings ShadowPassVertex(Attributes input)
{
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    output.positionCS = GetShadowPositionHClip(input);
    return output;
}

half4 ShadowPassFragment(Varyings input) : SV_TARGET
{
    Alpha(SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a, _BaseColor, _Cutoff);
    return 0;
}

#endif
			Name "ShadowCaster"
            Tags{ "LightMode" = "ShadowCaster" }  
            Cull Off                  
            HLSLPROGRAM
                                                       
            void vertex_shader (inout float4 vertex:POSITION,inout float2 uv:TEXCOORD0,uint i:SV_InstanceID)
            {              
                vertex = mul(UNITY_MATRIX_VP,GeometryBuffer[i]+vertex);
            }
           
            float4 pixel_shader (float4 vertex:POSITION, float2 uv:TEXCOORD0) : SV_Target
            {
                float4 color = tex2D(GrassTexture,uv);              
                clip (color.a-CutOff);
                return 0;
            }
            ENDHLSL
        } 
		*/
		
	}

	 FallBack "Hidden/Universal Render Pipeline/FallbackError"

}