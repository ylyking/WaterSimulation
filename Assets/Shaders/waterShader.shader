﻿Shader "Custom/WaterShader" {
	Properties {
		_Color ("Main Color", Color) = (1,1,1,1)
		_SpecColor ("Specular Color", Color) = (1.0, 1.0, 1.0, 1.0)
		_Shininess ("Shininess", Range(0.1, 10.0)) = 3.0
		_SunPower ("Sun Power", Float) = 1.0
		_NumWaves ("Number of waves", Range(1,32)) = 4
		_BumpDepth ("Bump depth", Range(0, 1.0)) = 1.0
		_BumpMap ("Bump Map", 2D) = "bump" {}
		_BumpMap2 ("Bump Map 2", 2D) = "bump" {}
		_ReflecTivity("Reflectivity", Range(0.0, 5.0)) = 1.0
		_ReflMap("Reflection Map", Cube) = "cube" {}
	}
	SubShader {
		Pass{
			Tags {"LightMode" = "ForwardBase"}
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			uniform float4 _Color;
			uniform float4 _SpecColor;
			uniform float _Shininess;
			uniform half _SunPower;
			uniform half _NumWaves;

			uniform half _BumpDepth;
			uniform sampler2D _BumpMap;
			uniform float4 _BumpMap_ST;
			uniform sampler2D _BumpMap2;
			uniform float4 _BumpMap2_ST;

			uniform half _ReflecTivity;
			uniform samplerCUBE _ReflMap;
			
			// private values
			uniform float3 _SunDir;
			uniform float3 _SunColor;
			uniform float4x4 _Waves;
			uniform float4x4 _Waves2;
			uniform float4x4 _Waves3;
			uniform float4x4 _Waves4;
			uniform float4x4 _Waves5;
			uniform float4x4 _Waves6;
			uniform float4x4 _Waves7;
			uniform float4x4 _Waves8;
			
			// Unity Defined uniforms
			uniform float4 _LightColor0;


			// THe struct describing a wave.
			struct Wave {
			  float freq;  // 2*PI / wavelength
			  float amp;   // amplitude
			  float phase; // speed * 2*PI / wavelength
			  float2 dir;
			};
			// compute the gerstner offset for one wave 
			float3 getGerstnerOffset(float2 x0, Wave w, float time)
			{
				float k = length(w.dir);
				float2 x = (w.dir / k)* w.amp * sin( dot( w.dir, x0) - w.freq * time +w.phase);
				float y = w.amp * cos( dot( w.dir, x0) - w.freq*time + w.phase);
				return float3(x.x, y, x.y);
			}

			// Helper function to compute the binormal of the offset wave point
			// This comes from the taking the derivative of the Gerstner surface in the x-direction
			float3 computeBinormal(float2 x0, Wave w, float time)
			{
				float3 B = float3(0, 0, 0);
				half k = length(w.dir);
				B.x = w.amp * (pow(w.dir.x, 2) / k) * cos( dot(w.dir, x0) - w.freq * time + w.phase);
				B.y = -w.amp * w.dir.x * sin( dot(w.dir, x0) - w.freq * time + w.phase);
				B.z = w.amp * ((w.dir.y * w.dir.x)/ k) * cos( dot(w.dir, x0) - w.freq * time + w.phase);
				return B;
			}

			// Helper function to compute the tangent vector of the offset wave point
			// This comes from the taking the derivative of the Gerstner surface in the z-direction
			float3 computeTangent(float2 x0, Wave w, float time)
			{
				float3 T = float3(0, 0, 0);
				half k = length(w.dir);
				T.x = w.amp * ((w.dir.y * w.dir.x)/ k) * cos( dot(w.dir, x0) - w.freq * time + w.phase);
				T.y = -w.amp * w.dir.x * sin( dot(w.dir, x0) - w.freq * time + w.phase);
				T.z = w.amp * (pow(w.dir.y, 2) / k) * cos( dot(w.dir, x0) - w.freq * time + w.phase);
				return T;		
			}

			float fresnel(float3 V, float3 N)
			{	
				
				half NdotL = max( dot(V, N), 0.0);
				half fresnelBias = 0.4;
				half fresnelPow = 5.0;
				fresnelPow = _SunPower;

				half facing  = (1.0 - NdotL);
				return max( fresnelBias + (1-fresnelBias) * pow(facing, fresnelPow), 0.0);

				/*
				half n1 = 1.0;
				half n2 = 1.333;
				float cosTheta_i = abs( dot(V, N) );
				float theta_i = acos( cosTheta_i );

				float inner = sqrt( 1 - pow((n1/n2 * sin(theta_i)), 2));
				float numerator =  (n1 * cosTheta_i) - (n2 * inner);
				float denominator = (n1 * cosTheta_i) + (n2 * inner);
				float Rs = pow( abs(numerator/denominator), 2);
				numerator = (n1*inner) - (n2 * cosTheta_i);
				denominator = (n1*inner) + (n2 * cosTheta_i);
				float Rt = pow( abs(numerator/denominator), 2);
				
				return (Rs + Rt) / 2 * 2;
				*/
			}	

			float3 computeSunColor(float3 V, float3 N)
			{
				float3 HalfVector = normalize( abs( -V + _SunDir));
				return _SunColor * pow( abs( dot(HalfVector, N)), _SunPower);
			}

			// Input struct for vertex shader
			struct VertexInput {
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 texcoord : TEXCOORD0;
				float4 tangent : TANGENT;

			};

			// Output struct from vertex shader and input to fragment shader
			struct VertexOutput {
				float4 pos : POSITION;
				float4 tex : TEXCOORD0;
				float4 posWorld : TEXCOORD1;
				float3 normalDir : TEXCOORD2;
				float3 tangentWorld : TEXCOORD3;
				float3 binormalWorld : TEXCOORD4;
			};

			VertexOutput vert(VertexInput vIn) 
			{
				VertexOutput vOut;
				Wave W[32];
				/*float4x4 matrices[8] = {_Waves, _Waves2,_Waves3,_Waves4,_Waves5,_Waves6,_Waves7,_Waves8};
				for(int i = 0; i < 8; i++)
				{
					float4x4 M = matrices[i];
					for(int j = 0; j < 4; j++)
					{
						float4 row = M[j];
						Wave w = {row.x, row.y, 0.10, float2(row.z, row.w)};
						W[j] = w;
					}
				}
				*/

				for(int i = 0; i < 4; i++)
				{
					float4 row = _Waves[i];
					Wave af = {row.x, row.y, 0.10, float2(row.z, row.w)};
					W[i] = af;
				}

				for(int i = 0; i < 4; i++)
				{
					float4 row = _Waves2[i];
					Wave af = {row.x, row.y, 0.10, float2(row.z, row.w)};
					W[i+4] = af;
				}
				for(int i = 0; i < 4; i++)
				{
					float4 row = _Waves3[i];
					Wave af = {row.x, row.y, 0.10, float2(row.z, row.w)};
					W[i+8] = af;
				}
				for(int i = 0; i < 4; i++)
				{
					float4 row = _Waves4[i];
					Wave af = {row.x, row.y, 0.10, float2(row.z, row.w)};
					W[i+12] = af;
				}

				for(int i = 0; i < 4; i++)
				{
					float4 row = _Waves5[i];
					Wave af = {row.x, row.y, 0.10, float2(row.z, row.w)};
					W[i+16] = af;
				}
				for(int i = 0; i < 4; i++)
				{
					float4 row = _Waves6[i];
					Wave af = {row.x, row.y, 0.10, float2(row.z, row.w)};
					W[i+20] = af;
				}
				for(int i = 0; i < 4; i++)
				{
					float4 row = _Waves7[i];
					Wave af = {row.x, row.y, 0.10, float2(row.z, row.w)};
					W[i+24] = af;
				}
				for(int i = 0; i < 4; i++)
				{
					float4 row = _Waves8[i];
					Wave af = {row.x, row.y, 0.10, float2(row.z, row.w)};
					W[i+28] = af;
				}

				// save the original point on the horizontal plane as x0
				half2 x0 = vIn.vertex.xz;
				float3 newPos = float3(0.0, 0.0, 0.0);
				float3 tangent = float3(0, 0, 0);
				float3 binormal = float3(0, 0, 0);

				half nw = trunc(_NumWaves);

				// iterate and sum together all waves.
				for(int i = 0; i < nw; i++)
				{
					Wave w = W[i];
					newPos += getGerstnerOffset(x0, w, _Time.y);
					binormal += computeBinormal(x0, w, _Time.y);
					tangent += computeTangent(x0, w, _Time.y);
				}
				// fix binormal and tangent
				binormal.x = 1 - binormal.x;
				binormal.z = 0 - binormal.z;

				tangent.x = 0 - tangent.x;
				tangent.z = 1 - tangent.z;
				// displace vertex 
				vIn.vertex.x -= newPos.x;
				vIn.vertex.z -= newPos.z;
				vIn.vertex.y = newPos.y;
				vOut.pos = mul(UNITY_MATRIX_MVP, vIn.vertex);		// transform from local to screen space
				vOut.posWorld = mul(_Object2World, vIn.vertex);		// transform from local to world space
				//vOut.posWorld = mul(_Object2World, vIn.vertex);		// transform from local to world space
				vOut.tangentWorld = normalize( mul( float4(tangent.xyz, 0.0), _Object2World).xyz);
				vOut.binormalWorld = normalize( mul( float4(binormal.xyz, 0.0), _Object2World).xyz);
				vOut.normalDir = normalize( cross( vOut.tangentWorld, vOut.binormalWorld) * vIn.tangent.w);
				vOut.tex = vIn.texcoord;
				//vOut.pos = mul(UNITY_MATRIX_MVP, vIn.vertex);		// transform from local to screen space

				return vOut;
			}

			float4 frag(VertexOutput i) : COLOR
			{
				
				float3 vDir = normalize( _WorldSpaceCameraPos.xyz - i.posWorld.xyz); // compute view direction (posWorld -> cameraPos)
				float3 lDir;

				float atten;
				if(_WorldSpaceLightPos0.w == 0.0) //  Directional light
				{
					atten = 1.0;
					lDir = normalize( _WorldSpaceLightPos0.xyz );
					lDir = _SunDir;
				} else {
					float3 fragToLight = _WorldSpaceLightPos0.xyz - i.posWorld ;
					atten = 1.0 / length(fragToLight);
					lDir = normalize ( fragToLight );
				}

				// texture map
				//float4 tex = tex2D( _MainTex, i.tex.xy * _MainTex_ST.xy + _MainTex_ST.zw );
				float4 texN = tex2D( _BumpMap, i.tex.xy * _BumpMap_ST.xy + _BumpMap_ST.zw );
				float4 texN2 = tex2D( _BumpMap2, i.tex.xy * _BumpMap2_ST.xy + _BumpMap2_ST.zw );

				// unpack normal
				float3 localCoords = float3(2.0 * texN.ag - float2(1.0, 1.0), 0.0);
				float3 localCoords2 = float3(2.0 * texN2.ag - float2(1.0, 1.0), 0.0);
				//localCoords.z = 1.0 - 0.5 * dot( localCoords, localCoords)
				localCoords.z = _BumpDepth;
				localCoords2.z = _BumpDepth;

				// normal transpose matrix
				float3x3 local2WorldTranspose = float3x3(i.tangentWorld, i.binormalWorld, i.normalDir);

				float3 nDir = normalize( mul( localCoords, local2WorldTranspose) );
				float3 nDir2 = normalize( mul( localCoords2, local2WorldTranspose) );
				nDir = normalize(nDir + nDir2);
			    float3 ambientLight = UNITY_LIGHTMODEL_AMBIENT.rgb * _Color.rgb;
				// diffuse lighting
				float3 diffRefl = atten * _LightColor0.xyz * saturate( dot( nDir, lDir) );
				// specular
				float3 specRefl = diffRefl * _SpecColor.xyz * pow( saturate( dot( reflect( -lDir, nDir), vDir) ), _Shininess);


				float f = fresnel(vDir, nDir);
				//float3 skyColor = texCUBE(_ReflMap, WorldReflectionVector(IN, o.Normal)).rgb * _ReflecTivity;//* _ReflecTivity;
				float3 reflectedDir = reflect(-vDir, normalize(nDir));
				float3 sunColor = computeSunColor(vDir, nDir);
				float3 skyColor = texCUBE(_ReflMap, reflectedDir).rgb * _ReflecTivity;//flip x
				float3 lightFinal = ambientLight + diffRefl + specRefl;
				
				//lightFinal = lerp( lightFinal, skyColor, f);
				lightFinal = lerp( lightFinal, skyColor, f);// + sunColor;		
				//lightFinal = float4(sunColor, 1.0);
				//turn float4(skyColor, 1.0);
				return float4(lightFinal * _Color.rgb, 1.0);
			}
			ENDCG
		}
	}
	FallBack "Diffuse"
}
