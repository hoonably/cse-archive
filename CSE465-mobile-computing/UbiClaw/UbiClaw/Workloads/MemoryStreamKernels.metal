#include <metal_stdlib>
using namespace metal;

struct AnimationParticle {
    float2 startPosition;
    float2 velocity;
    float hue;
    float size;
};

struct AnimationConnection {
    uint sourceIndex;
    uint targetIndex;
};

struct AnimationUniforms {
    float time;
    float2 viewportSize;
};

struct AnimationVertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

float triangleWave(float value) {
    float wrapped = fmod(value, 2.0);
    float positive = wrapped < 0.0 ? wrapped + 2.0 : wrapped;
    return positive <= 1.0 ? positive : 2.0 - positive;
}

float2 particlePosition(AnimationParticle particle, float time) {
    return float2(
        triangleWave(particle.startPosition.x + particle.velocity.x * time),
        triangleWave(particle.startPosition.y + particle.velocity.y * time)
    );
}

float2 clipSpace(float2 normalizedPosition) {
    return float2(normalizedPosition.x * 2.0 - 1.0, 1.0 - normalizedPosition.y * 2.0);
}

float3 hsvToRgb(float h, float s, float v) {
    float3 shift = float3(0.0, 2.0 / 3.0, 1.0 / 3.0);
    float3 p = abs(fract(h + shift) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

kernel void memoryStreamKernel(
    const device float *inputA [[buffer(0)]],
    const device float *inputB [[buffer(1)]],
    device float *output [[buffer(2)]],
    constant uint &elementCount [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= elementCount) {
        return;
    }

    output[id] = inputA[id] * 0.6f + inputB[id] * 0.4f;
}

vertex AnimationVertexOut animationParticleVertex(
    uint vertexID [[vertex_id]],
    const device AnimationParticle *particles [[buffer(0)]],
    constant AnimationUniforms &uniforms [[buffer(1)]]
) {
    AnimationParticle particle = particles[vertexID];
    float2 position = particlePosition(particle, uniforms.time);
    float hue = fract(particle.hue + uniforms.time * 0.05);

    AnimationVertexOut out;
    out.position = float4(clipSpace(position), 0.0, 1.0);
    out.color = float4(hsvToRgb(hue, 0.8, 0.9), 0.58);
    out.pointSize = particle.size * 2.0;
    return out;
}

vertex AnimationVertexOut animationLineVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device AnimationConnection *connections [[buffer(0)]],
    const device AnimationParticle *particles [[buffer(1)]],
    constant AnimationUniforms &uniforms [[buffer(2)]]
) {
    AnimationConnection connection = connections[instanceID];
    AnimationParticle source = particles[connection.sourceIndex];
    AnimationParticle target = particles[connection.targetIndex];

    float2 sourcePosition = particlePosition(source, uniforms.time);
    float2 targetPosition = particlePosition(target, uniforms.time);
    float2 deltaPixels = (sourcePosition - targetPosition) * uniforms.viewportSize;
    float distancePixels = length(deltaPixels);
    float alpha = distancePixels < 60.0 ? 0.4 * (1.0 - distancePixels / 60.0) : 0.0;

    AnimationVertexOut out;
    float2 position = vertexID == 0 ? sourcePosition : targetPosition;
    out.position = float4(clipSpace(position), 0.0, 1.0);
    out.color = float4(1.0, 1.0, 1.0, alpha);
    out.pointSize = 1.0;
    return out;
}

fragment float4 animationColorFragment(AnimationVertexOut in [[stage_in]]) {
    return in.color;
}

fragment float4 animationParticleFragment(
    AnimationVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    float2 centered = pointCoord * 2.0 - 1.0;
    float radiusSquared = dot(centered, centered);

    if (radiusSquared > 1.0) {
        discard_fragment();
    }

    float radius = sqrt(radiusSquared);
    float edgeWidth = max(fwidth(radius) * 1.5, 0.015);
    float edgeAlpha = 1.0 - smoothstep(1.0 - edgeWidth, 1.0, radius);
    float radialAlpha = mix(0.72, 1.0, 1.0 - radius);
    return float4(in.color.rgb, in.color.a * edgeAlpha * radialAlpha);
}

struct Game3DVertex {
    float3 position;
    float3 normal;
};

struct Game3DInstance {
    float4x4 modelMatrix;
    float4 color;
};

struct Game3DUniforms {
    float4x4 viewProjectionMatrix;
    float4x4 shadowMatrix;
    float3 lightDirection;
    float time;
    float3 cameraPosition;
    float fogDensity;
};

struct Game3DVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float4 shadowPosition;
    float4 color;
};

vertex Game3DVertexOut game3DVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device Game3DVertex *vertices [[buffer(0)]],
    const device Game3DInstance *instances [[buffer(1)]],
    constant Game3DUniforms &uniforms [[buffer(2)]]
) {
    Game3DVertex inputVertex = vertices[vertexID];
    Game3DInstance inputInstance = instances[instanceID];

    float4 worldPosition = inputInstance.modelMatrix * float4(inputVertex.position, 1.0);
    float3x3 normalMatrix = float3x3(
        inputInstance.modelMatrix[0].xyz,
        inputInstance.modelMatrix[1].xyz,
        inputInstance.modelMatrix[2].xyz
    );

    Game3DVertexOut out;
    out.position = uniforms.viewProjectionMatrix * worldPosition;
    out.worldPosition = worldPosition.xyz;
    out.worldNormal = normalize(normalMatrix * inputVertex.normal);
    out.shadowPosition = uniforms.shadowMatrix * worldPosition;
    out.color = inputInstance.color;
    return out;
}

fragment float4 game3DFragment(
    Game3DVertexOut in [[stage_in]],
    texture2d<float> shadowTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant Game3DUniforms &uniforms [[buffer(0)]]
) {
    float3 normal = normalize(in.worldNormal);
    float3 lightDir = normalize(-uniforms.lightDirection);
    float3 viewDir = normalize(uniforms.cameraPosition - in.worldPosition);
    float3 halfVector = normalize(lightDir + viewDir);

    float diffuse = max(dot(normal, lightDir), 0.0);
    float specular = pow(max(dot(normal, halfVector), 0.0), 24.0);
    float rim = pow(1.0 - max(dot(normal, viewDir), 0.0), 2.0);

    float3 shadowCoord = in.shadowPosition.xyz / max(in.shadowPosition.w, 0.0001);
    float shadow = 1.0;
    bool insideShadowMap =
        shadowCoord.x >= 0.0 && shadowCoord.x <= 1.0 &&
        shadowCoord.y >= 0.0 && shadowCoord.y <= 1.0 &&
        shadowCoord.z >= 0.0 && shadowCoord.z <= 1.0;
    if (insideShadowMap) {
        float2 texelSize = 1.0 / float2(shadowTexture.get_width(), shadowTexture.get_height());
        float bias = max(0.0015, 0.005 * (1.0 - diffuse));
        float visibility = 0.0;
        const float2 pcfOffsets[4] = {
            float2(-0.5, -0.5),
            float2( 0.5, -0.5),
            float2(-0.5,  0.5),
            float2( 0.5,  0.5)
        };
        for (uint i = 0; i < 4; ++i) {
            float sampleDepth = shadowTexture.sample(textureSampler, shadowCoord.xy + pcfOffsets[i] * texelSize).r;
            visibility += shadowCoord.z - bias <= sampleDepth ? 1.0 : 0.18;
        }
        shadow = visibility * 0.25;
    }

    float distanceToCamera = distance(uniforms.cameraPosition, in.worldPosition);
    float fog = 1.0 - exp(-distanceToCamera * uniforms.fogDensity);

    float3 skyColor = mix(float3(0.03, 0.05, 0.10), float3(0.18, 0.28, 0.42), clamp(in.worldPosition.y * 0.03 + 0.4, 0.0, 1.0));
    float3 lit = in.color.rgb * (0.16 + diffuse * 0.84 * shadow);
    lit += specular * float3(1.0, 0.95, 0.8) * 0.35 * shadow;
    lit += rim * float3(0.2, 0.35, 0.5) * 0.28;

    float3 color = mix(lit, skyColor, fog);
    return float4(color, 1.0);
}

vertex float4 game3DFullscreenVertex(uint vertexID [[vertex_id]]) {
    const float2 quadVertices[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    return float4(quadVertices[vertexID], 0.0, 1.0);
}

fragment float4 game3DCompositeFragment(
    float4 position [[position]],
    texture2d<float> sceneTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant Game3DUniforms &uniforms [[buffer(0)]]
) {
    float2 uv = position.xy / float2(sceneTexture.get_width(), sceneTexture.get_height());

    float2 offset = float2(0.0014 * sin(uniforms.time * 0.7), 0.0011 * cos(uniforms.time * 0.5));
    float3 center = sceneTexture.sample(textureSampler, uv).rgb;
    float3 bloom =
        sceneTexture.sample(textureSampler, uv + float2(0.0022, 0.0)).rgb +
        sceneTexture.sample(textureSampler, uv - float2(0.0022, 0.0)).rgb +
        sceneTexture.sample(textureSampler, uv + float2(0.0, 0.0022)).rgb +
        sceneTexture.sample(textureSampler, uv - float2(0.0, 0.0022)).rgb +
        sceneTexture.sample(textureSampler, uv + float2(0.0036, 0.0036)).rgb +
        sceneTexture.sample(textureSampler, uv - float2(0.0036, 0.0036)).rgb +
        sceneTexture.sample(textureSampler, uv + float2(-0.0036, 0.0036)).rgb +
        sceneTexture.sample(textureSampler, uv + float2(0.0036, -0.0036)).rgb;
    bloom *= 0.125;

    float red = sceneTexture.sample(textureSampler, uv + offset).r;
    float green = center.g;
    float blue = sceneTexture.sample(textureSampler, uv - offset).b;
    float3 color = float3(red, green, blue);
    color += bloom * 0.22;

    float radial = length(uv * 2.0 - 1.0);
    float vignette = smoothstep(1.35, 0.2, radial);
    float scanline = 0.99 + 0.01 * sin((uv.y + uniforms.time * 0.04) * 1800.0);
    color *= vignette * scanline;

    return float4(color, 1.0);
}
