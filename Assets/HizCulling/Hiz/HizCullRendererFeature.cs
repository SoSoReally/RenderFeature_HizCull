namespace UnityEngine.Rendering.Universal
{
    public class HizCullRendererFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        class HizCullSetting : System.IDisposable
        {
            public bool Enable;
            public bool Update;
            public int Density;

            public Mesh TargetMesh;
            public Material TargetMaterial;
            public ComputeShader CullShader;
            public ComputeShader GenerateMipmap;
            public TerrainData Terrain;



            public bool Toggle;
            public Vector2 RandomValue;

            [HideInInspector]
            public HizCullData Data;

            public RenderTexture GameDepthTempRT;

            public void Dispose()
            {
                RenderTexture.ReleaseTemporary(GameDepthTempRT);
            }
        }

        class HizCullData
        {
            public ComputeBuffer PosAllBuffer;
            public ComputeBuffer BufferWithArags;
            public ComputeBuffer VisPosBuffer;
            public int PositionBufferID;
            public int VisPositionBufferID;
            public int BufferArgsID;
            public int VPID;
            public int KernelID;
            public int GenerateMiamapKernelID;
            public int Count;
            public int Width_x;
            public int Width_z;
            //public Matrix4x4[] ArrayTRS;
            public uint[] Args;
            public RenderTargetIdentifier DepthTargetIdentifier;
            public int DepthTextureID = Shader.PropertyToID("_CameraDepthTexture");
            public int SoureceTexID = Shader.PropertyToID("_SoureceTex");
            public int ResultID = Shader.PropertyToID("_Result");
            public RenderTargetIdentifier CurrentPassQueueRenderTexture;
            public CameraType CameraType;

            public int MainShadowTextureID = Shader.PropertyToID("_MainLightShadowmapTexture");
        }

        HizCullPass m_hizCullPass;
        HizCullPassDraw m_hizCullPassDraw;
        HizCullPassShadow m_hizCullPassShadow;
        [SerializeField]
        HizCullSetting m_HizCullSetting;

        public RenderPassEvent HizCull = RenderPassEvent.BeforeRendering;
        public RenderPassEvent HizCullDraw = RenderPassEvent.AfterRenderingOpaques;
        public RenderPassEvent HizCullShadow = RenderPassEvent.AfterRenderingShadows;

        public int EventOffest;
        /// <inheritdoc/>
        public override void Create()
        {
            //SetActive(false);
            if (!m_HizCullSetting.Terrain)
            {
                SetActive(false);
                return;
            }

            m_HizCullSetting.Data = new HizCullData();
            var data = m_HizCullSetting.Data;
            data.PositionBufferID = Shader.PropertyToID("AllPositionBuffer");
            data.VisPositionBufferID = Shader.PropertyToID("visPositionBuffer");
            data.BufferArgsID = Shader.PropertyToID("bufferArgs");
            data.KernelID = m_HizCullSetting.CullShader.FindKernel("CSMain");
            data.VPID = Shader.PropertyToID("VP");

            m_HizCullSetting.Density = m_HizCullSetting.Density > 0 ? m_HizCullSetting.Density : 1;
            var offest = m_HizCullSetting.Terrain.size;
            offest.y = 0;
            data.Width_x = (int)offest.x;
            data.Width_z = (int)offest.z;
            data.Count = data.Width_x * data.Width_z * m_HizCullSetting.Density;
            data.PosAllBuffer = new ComputeBuffer(data.Count, 4 * 16);
            data.VisPosBuffer = new ComputeBuffer(data.Count, 4 * 16);

            var width_x = data.Width_x;
            var width_z = data.Width_z;
            var hizCullSetting = m_HizCullSetting;
            Matrix4x4[] object_M = new Matrix4x4[data.Count];
            //ArrayTRS = new Matrix4x4[data.count];
            for (int i = 0; i < data.Count; i++)
            {
                //pos[i] =  Random.insideUnitSphere*10;
                float x = (float)i / (width_x * hizCullSetting.Density);
                float z = ((float)i / hizCullSetting.Density) % width_z;

                var r = Random.insideUnitCircle;

                float y = hizCullSetting.Terrain.GetInterpolatedHeight(x / offest.x + r.x / offest.x * hizCullSetting.RandomValue.x, z / offest.z + r.y / offest.z * hizCullSetting.RandomValue.y);

                float angle_y = Random.Range(0f, 360f);

                float size = Random.Range(4f, 6f);
                
                 new Vector4(x, y, z, 4);
                object_M[i] = Matrix4x4.TRS(new Vector3(x, y, z), Quaternion.Euler(0f, angle_y, 0f), Vector3.one * size);
                //ArrayTRS[i] = Matrix4x4.TRS(pos[i], Quaternion.identity, Vector3.one);
            }
             

            //hizCullSetting.Terrain.terrainData.he


            data.PosAllBuffer.SetData(object_M);

            hizCullSetting.TargetMaterial.SetBuffer(data.PositionBufferID, data.PosAllBuffer);

            int submeshIndex = 0;
            data.Args = new uint[5] { 0, 0, 0, 0, 0 };
            data.Args[0] = hizCullSetting.TargetMesh.GetIndexCount(submeshIndex);
            data.Args[1] = (uint)(data.Count);
            data.Args[2] = hizCullSetting.TargetMesh.GetIndexStart(submeshIndex);
            data.Args[3] = hizCullSetting.TargetMesh.GetBaseVertex(submeshIndex);
            data.BufferWithArags = new ComputeBuffer(1, data.Args.Length * 4, ComputeBufferType.IndirectArguments);

            hizCullSetting.CullShader.SetBuffer(data.KernelID, data.PositionBufferID, data.PosAllBuffer);
            hizCullSetting.CullShader.SetBuffer(data.KernelID, data.VisPositionBufferID, data.VisPosBuffer);

            int[] length = { 100, hizCullSetting.Density };
            hizCullSetting.CullShader.SetInts("lengthX", length);
            data.GenerateMiamapKernelID = hizCullSetting.GenerateMipmap.FindKernel("Mipmap");

            //m_DepthTextureNormalizeMaterial = new Material(m_hizCullSetting.DepthTextureNormalize);
            data.DepthTextureID = Shader.PropertyToID("_CameraDepthTexture");
            data.DepthTargetIdentifier = new RenderTargetIdentifier(data.DepthTextureID);
            m_HizCullSetting.GameDepthTempRT = CreatMipmapDepth();



            m_hizCullPass = new HizCullPass(m_HizCullSetting) { renderPassEvent = HizCull + EventOffest };
            m_hizCullPassDraw = new HizCullPassDraw(m_HizCullSetting) { renderPassEvent = HizCullDraw + 10 };
            m_hizCullPassShadow = new HizCullPassShadow(m_HizCullSetting) { renderPassEvent = HizCullShadow + 10 };

        }

        private RenderTexture CreatMipmapDepth()
        {
            RenderTextureDescriptor rtd = new RenderTextureDescriptor(0, 0);
            rtd.autoGenerateMips = false;
            rtd.useMipMap = true;
            rtd.mipCount = 7;
            rtd.height = 512;
            rtd.width = 512;
            rtd.enableRandomWrite = true;
            rtd.colorFormat = RenderTextureFormat.RFloat;
            rtd.volumeDepth = 1;
            rtd.msaaSamples = 1;
            rtd.bindMS = false;
            rtd.dimension = TextureDimension.Tex2D;
            return RenderTexture.GetTemporary(rtd);
        }

        // Here you can inject one or multiple render passes in the renderer.
        // This method is called when setting up the renderer once per-camera.
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (!(renderingData.cameraData.cameraType == CameraType.Game || renderingData.cameraData.cameraType == CameraType.SceneView))
            {
                return;
            }

            //renderer.cameraColorTarget,并不是固定的,不透明之后的物体渲染会更新这个
            m_HizCullSetting.Data.CurrentPassQueueRenderTexture = renderer.cameraColorTarget;
            m_HizCullSetting.Data.CameraType = renderingData.cameraData.cameraType;
            renderer.EnqueuePass(m_hizCullPass);
            renderer.EnqueuePass(m_hizCullPassDraw);
            renderer.EnqueuePass(m_hizCullPassShadow);
        }

        protected override void Dispose(bool disposing)
        {
            base.Dispose(disposing);
            m_HizCullSetting.Dispose();
        }

        private void OnEnable()
        {
            //m_ScriptablePass = new HizCullPass(m_HizCullSetting)
            //{

            //    // Configures where the render pass should be injected.
            //    renderPassEvent = RPE + 10
            //};
        }

        class HizCullPass : ScriptableRenderPass
        {
            private HizCullSetting m_hizCullSetting;
            ProfilingSampler ProfilingSampler = new ProfilingSampler("HizCull");
            // This method is called before executing the render pass.
            // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
            // When empty this render pass will render to the active camera render target.
            // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
            // The render pipeline will ensure target setup and clearing happens in a performant manner.
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {

            }

            // Here you can implement the rendering logic.
            // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
            // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
            // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {


                if (m_hizCullSetting.Density <= 0)
                {
                    return;
                }

                var cmd = CommandBufferPool.Get();
                using var profScope = new ProfilingScope(cmd, ProfilingSampler);
                var cs = m_hizCullSetting.CullShader;
                var data = m_hizCullSetting.Data;
                var vp = GL.GetGPUProjectionMatrix(Camera.main.projectionMatrix, false) * Camera.main.worldToCameraMatrix;
                data.Args[1] = 0;
                var md = m_hizCullSetting.GameDepthTempRT;

                if (m_hizCullSetting.Toggle && data.CameraType == CameraType.Game)
                {

                    //m_hizCullSetting.Toggle = false;
                    var mipmap = m_hizCullSetting.GenerateMipmap;


                    //Graphics.Blit(depthTargetIdentifier, md);
                    //m_hizCullSetting.DepthTextureNormalize.SetTexture("_MainTex", d);

                    cmd.Blit(m_hizCullSetting.Data.DepthTargetIdentifier, md);//,m_hizCullSetting.DepthTextureNormalize,0);

                    var size = 512;
                    if (size % 2 == 0 && size > 8)
                    {
                        int maxlevel = Mathf.RoundToInt(Mathf.Log(512, 2));
                        int level = 0;
                        //Debug.Log(maxlevel);

                        //goto lerrr;
                        while (level < maxlevel - 3)
                        {

                            var current = level;
                            var next = ++level;
                            cmd.SetComputeTextureParam(mipmap, data.GenerateMiamapKernelID, data.SoureceTexID, md, current);
                            cmd.SetComputeTextureParam(mipmap, data.GenerateMiamapKernelID, data.ResultID, md, next);
                            //level++;
                            var dis = (1 << (maxlevel - level)) / 8;
                            //Debug.Log(dis);
                            cmd.DispatchCompute(mipmap, data.GenerateMiamapKernelID, dis, dis, 1);
                            cmd.SetRenderTarget(md);

                        }
                    }
                }

                //m_bufferWithArags.SetData(args);
                //m_hizCullSetting.CullShader.SetMatrix(vpID, vp);
                //m_hizCullSetting.CullShader.SetBuffer(kernelID, bufferArgsID, m_bufferWithArags);
                //m_hizCullSetting.CullShader.Dispatch(kernelID, (width_x) / 25, (width_z) / 25, m_hizCullSetting.Density);
                //m_hizCullSetting.TargetMaterial.SetBuffer(visPositionBufferID, m_visPosBuffer);


                //commondbuffer 执行方式
                cmd.SetBufferData(data.BufferWithArags, data.Args);
                cmd.SetComputeMatrixParam(cs, data.VPID, vp);
                cmd.SetComputeBufferParam(cs, data.KernelID, data.BufferArgsID, data.BufferWithArags);
                cmd.SetComputeBufferParam(cs, data.KernelID, data.PositionBufferID, data.PosAllBuffer);
                if (md != null)
                {
                    cmd.SetComputeTextureParam(cs, data.KernelID, "_HizDepthMipmap", md);
                }
                cmd.DispatchCompute(cs, data.KernelID, (data.Width_x) / 25, (data.Width_z) / 25, m_hizCullSetting.Density);

                m_hizCullSetting.TargetMaterial.SetBuffer(data.VisPositionBufferID, data.VisPosBuffer);
                m_hizCullSetting.TargetMaterial.EnableKeyword("INSTANCING_ON");
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
            // Cleanup any allocated resources that were created during the execution of this render pass.
            public override void OnCameraCleanup(CommandBuffer cmd)
            {

            }

            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
            {



            }

            public override void OnFinishCameraStackRendering(CommandBuffer cmd)
            {
                //RenderTexture.ReleaseTemporary(GameDepthTempRT);
            }
            public HizCullPass(HizCullSetting hizCullSetting)
            {
                m_hizCullSetting = hizCullSetting;

            }
        }

        class HizCullPassDraw : ScriptableRenderPass
        {
            HizCullSetting m_hizCullSetting;
            public HizCullPassDraw(HizCullSetting hizCullSetting)
            {
                m_hizCullSetting = hizCullSetting;
                profilingSampler = new ProfilingSampler("HizCullDraw");
            }
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using ProfilingScope scope = new ProfilingScope(cmd, profilingSampler);
                cmd.DrawMeshInstancedIndirect(m_hizCullSetting.TargetMesh, 0, m_hizCullSetting.TargetMaterial, 0, m_hizCullSetting.Data.BufferWithArags);
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }

        class HizCullPassShadow : ScriptableRenderPass
        {
            private HizCullSetting m_hizCullSetting;
            public HizCullPassShadow(HizCullSetting hizCullSetting)
            {
                m_hizCullSetting = hizCullSetting;
                profilingSampler = new ProfilingSampler("HizCullShadow");
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using var scope = new ProfilingScope(cmd, profilingSampler);
                ref var rd = ref renderingData;
                if (!rd.shadowData.supportsMainLightShadows)
                    return;

                int shadowLightIndex = rd.lightData.mainLightIndex;
                if (shadowLightIndex == -1)
                {
                    return;
                }

                Bounds bounds = new Bounds();

                VisibleLight shadowLight = rd.lightData.visibleLights[shadowLightIndex];
                var Light = shadowLight.light;
                if (Light.shadows == LightShadows.None)
                {
                    return;
                }
                if (shadowLight.lightType != LightType.Directional)
                {
                    return;
                }

                if (!rd.cullResults.GetShadowCasterBounds(shadowLightIndex, out bounds))
                {
                    return;
                }

                var m_shadowCasterCascadesCount = rd.shadowData.mainLightShadowCascadesCount;
                int shadowResolution = ShadowUtils.GetMaxTileResolutionInAtlas(renderingData.shadowData.mainLightShadowmapWidth,
                    renderingData.shadowData.mainLightShadowmapHeight, m_shadowCasterCascadesCount);
                var width = rd.shadowData.mainLightShadowmapWidth;
                var height = (m_shadowCasterCascadesCount == 2) ?
                    renderingData.shadowData.mainLightShadowmapHeight >> 1 :
                    renderingData.shadowData.mainLightShadowmapHeight;
                Vector4 distance = new Vector4();
                ShadowSliceData shadowSliceData = new ShadowSliceData();
                if (m_shadowCasterCascadesCount > 1)
                {

                    m_hizCullSetting.TargetMaterial.EnableKeyword("_MAIN_LIGHT_SHADOWS_CASCADE_CC");
                }
                else
                {
                    m_hizCullSetting.TargetMaterial.DisableKeyword("_MAIN_LIGHT_SHADOWS_CASCADE_CC");
                }
                for (int cascadeIndex = 0; cascadeIndex < m_shadowCasterCascadesCount; ++cascadeIndex)
                {
                    bool success = ShadowUtils.ExtractDirectionalLightMatrix(ref rd.cullResults, ref rd.shadowData, shadowLightIndex, cascadeIndex, width, height, shadowResolution, Light.shadowNearPlane, out distance, out shadowSliceData);
                    if (!success)
                        return;
                    if (m_hizCullSetting.Data.MainShadowTextureID == 0)
                        return;
                    cmd.SetGlobalDepthBias(1.0f, 2.5f);
                    cmd.SetViewport(new Rect(shadowSliceData.offsetX, shadowSliceData.offsetY, shadowSliceData.resolution, shadowSliceData.resolution));
                    cmd.SetViewProjectionMatrices(shadowSliceData.viewMatrix, shadowSliceData.projectionMatrix);
                    //Shader.GetGlobalTexture(m_hizCullSetting.Data.MainShadowTextureID);

                    cmd.SetRenderTarget(m_hizCullSetting.Data.MainShadowTextureID);
                    cmd.DrawMeshInstancedIndirect(m_hizCullSetting.TargetMesh, 0, m_hizCullSetting.TargetMaterial, 1, m_hizCullSetting.Data.BufferWithArags);
                }


                cmd.SetGlobalDepthBias(0, 0);
                cmd.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(), renderingData.cameraData.GetProjectionMatrix());
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
                //var shadowmap = Shader.GetGlobalTexture("_MainLightShadowmapTexture");
                //cmd.SetRenderTarget(CurrentPassQueueRenderTexture);
                //cmd.SetRenderTarget(shadowmap);

                /*
                ref var renderingData = ref RD;


                if (!renderingData.shadowData.supportsMainLightShadows)
                    return;
                int shadowLightIndex = renderingData.lightData.mainLightIndex;
                if (shadowLightIndex == -1)
                    return;
                Bounds bounds;
                VisibleLight shadowLight = renderingData.lightData.visibleLights[shadowLightIndex];
                Light light = shadowLight.light;
                if (light.shadows == LightShadows.None)
                    return;

                if (shadowLight.lightType != LightType.Directional)
                {
                    Debug.LogWarning("Only directional lights are supported as main light.");
                }
                if (!renderingData.cullResults.GetShadowCasterBounds(shadowLightIndex, out bounds))
                    return;

                var m_ShadowCasterCascadesCount = renderingData.shadowData.mainLightShadowCascadesCount;

                int shadowResolution = ShadowUtils.GetMaxTileResolutionInAtlas(renderingData.shadowData.mainLightShadowmapWidth,
                    renderingData.shadowData.mainLightShadowmapHeight, m_ShadowCasterCascadesCount);
                var m_ShadowmapWidth = renderingData.shadowData.mainLightShadowmapWidth;
                var m_ShadowmapHeight = (m_ShadowCasterCascadesCount == 2) ?
                    renderingData.shadowData.mainLightShadowmapHeight >> 1 :
                    renderingData.shadowData.mainLightShadowmapHeight;
                ShadowSliceData ssd = new ShadowSliceData();
                Vector4 distance;
                for (int cascadeIndex = 0; cascadeIndex < m_ShadowCasterCascadesCount; ++cascadeIndex)
                {
                    bool success = ShadowUtils.ExtractDirectionalLightMatrix(ref renderingData.cullResults, ref renderingData.shadowData,
                        shadowLightIndex, cascadeIndex, m_ShadowmapWidth, m_ShadowmapHeight, shadowResolution, light.shadowNearPlane,
                        out distance, out ssd);

                    if (!success)
                        return;
                }
                cmd.SetGlobalDepthBias(1.0f, 2.5f);
                cmd.SetViewport(new Rect(ssd.offsetX, ssd.offsetY, ssd.resolution, ssd.resolution));
                cmd.SetViewProjectionMatrices(ssd.viewMatrix, ssd.projectionMatrix);
                cmd.SetRenderTarget(shadowmap, shadowmap);

                cmd.DrawMeshInstancedIndirect(m_hizCullSetting.TargetMesh, 0, m_hizCullSetting.TargetMaterial, 1, m_bufferWithArags);
                //cmd.SetRenderTarget(CurrentPassQueueRenderTexture);
                cmd.SetGlobalDepthBias(0, 0);
                //cmd.SetGlobalTexture("_MainLightShadowmapTexture", shadowmap);
                cmd.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(), renderingData.cameraData.GetProjectionMatrix());
                */
            }
        }

    }


}