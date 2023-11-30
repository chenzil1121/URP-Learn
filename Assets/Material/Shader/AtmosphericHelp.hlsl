#ifndef __ATMOSPHERE_HELP__
#define __ATMOSPHERE_HELP__

#ifndef PI
#define PI 3.1415926535
#endif

float3 _GroundColor;
float _PlanetRadius;
float _AtmosphereHeight;
float _SunLightIntensity;
float3 _SunLightColor;
float _SunDiskSize;
float _RayleighScatteringScale;
float _RayleighScatteringScalarHeight;
float _MieScatteringScale;
float _MieAnisotropy;
float _MieScatteringScalarHeight;
float _OzoneAbsorptionScale;
float _OzoneLevelCenterHeight;
float _OzoneLevelWidth;
#define N_SAMPLE 64

struct AtmosphereParameter
{
	float3 GroundColor;
	float PlanetRadius;
	float AtmosphereHeight;
	float SunLightIntensity;
	float3 SunLightColor;
	float SunDiskSize;
	float RayleighScatteringScale;
	float RayleighScatteringScalarHeight;
	float MieScatteringScale;
	float MieAnisotropy;
	float MieScatteringScalarHeight;
	float OzoneAbsorptionScale;
	float OzoneLevelCenterHeight;
	float OzoneLevelWidth;
};

AtmosphereParameter GetAtmosphereParameter()
{
	AtmosphereParameter param;

	param.GroundColor = _GroundColor;
	param.PlanetRadius = _PlanetRadius;
	param.AtmosphereHeight = _AtmosphereHeight;
	param.SunLightIntensity = _SunLightIntensity;
	param.SunLightColor = _SunLightColor;
	param.SunDiskSize = _SunDiskSize;
	param.RayleighScatteringScale = _RayleighScatteringScale;
	param.RayleighScatteringScalarHeight = _RayleighScatteringScalarHeight;
	param.MieScatteringScale = _MieScatteringScale;
	param.MieAnisotropy = _MieAnisotropy;
	param.MieScatteringScalarHeight = _MieScatteringScalarHeight;
	param.OzoneAbsorptionScale = _OzoneAbsorptionScale;
	param.OzoneLevelCenterHeight = _OzoneLevelCenterHeight;
	param.OzoneLevelWidth = _OzoneLevelWidth;

	return param;
}

//-----------------------------------------------------------------------------------------
// RaySphereIntersection 求直线与球交点
// 球方程 (P-C)^2 = R^2
// 射线方程 P = P0 + d * s
// 返回两个交点的根 d1，d2，其中d1 < d2，如果d < 0 ，说明交点在射线后方
//-----------------------------------------------------------------------------------------
float2 RaySphereIntersection(float3 rayOrigin, float3 rayDir, float3 sphereCenter, float sphereRadius)
{
	rayOrigin -= sphereCenter;
	float a = dot(rayDir, rayDir);
	float b = 2.0 * dot(rayOrigin, rayDir);
	float c = dot(rayOrigin, rayOrigin) - (sphereRadius * sphereRadius);
	float d = b * b - 4 * a * c;
	if (d < 0)
	{
		return -1;
	}
	else
	{
		d = sqrt(d);
		return float2(-b - d, -b + d) / (2 * a);
	}
}

//Rayleigh散射系数
float3 RayleighCoefficient(in AtmosphereParameter param, float h)
{
	//RGB三种单色光贡献的波长项
	const float3 sigma = float3(5.802, 13.558, 33.1) * 1e-6;
	//
	float H_R = param.RayleighScatteringScalarHeight;
	float rho_h = exp(-(h / H_R));
	return sigma * rho_h;
}
//Rayleigh散射相位函数
float RayleiPhase(float cos_theta)
{
	return (3.0 / (16.0 * PI)) * (1.0 + cos_theta * cos_theta);
}
//Mie散射系数
float3 MieCoefficient(in AtmosphereParameter param, float h)
{
	//Mie是针对大于光波长的粒子，因此与波长无关
	const float3 sigma = (3.996 * 1e-6).xxx;
	float H_M = param.MieScatteringScalarHeight;
	float rho_h = exp(-(h / H_M));
	return sigma * rho_h;
}
//Mie散射相位函数
float MiePhase(in AtmosphereParameter param, float cos_theta)
{
	float g = param.MieAnisotropy;

	float a = 3.0 / (8.0 * PI);
	float b = (1.0 - g * g) / (2.0 + g * g);
	float c = 1.0 + cos_theta * cos_theta;
	float d = pow(1.0 + g * g - 2 * g * cos_theta, 1.5);

	return a * b * (c / d);
}
//单独对太阳的光晕做处理
float MiePhaseHG(float cosAngle, float g)
{
	float oneMinusG = 1 - g;
	float g2 = g * g;
	return (1.0 / (4.0 * PI)) * oneMinusG * oneMinusG / pow(abs(1.0 + g2 - 2.0 * g * cosAngle), 3.0 / 2.0);
}

float3 MieAbsorption(in AtmosphereParameter param, float h)
{
	const float3 sigma = (4.4 * 1e-6).xxx;
	float H_M = param.MieScatteringScalarHeight;
	float rho_h = exp(-(h / H_M));
	return sigma * rho_h;
}

float3 OzoneAbsorption(in AtmosphereParameter param, float h)
{
#define sigma_lambda (float3(0.650f, 1.881f, 0.085f)) * 1e-6
	float center = param.OzoneLevelCenterHeight;
	float width = param.OzoneLevelWidth;
	float rho = max(0, 1.0 - (abs(h - center) / width));
	return sigma_lambda * rho;
}

float3 Scattering(in AtmosphereParameter param, float3 p, float3 lightDir, float3 viewDir)
{
	float3 planetCenter = float3(0, -param.PlanetRadius, 0);
	float cos_theta = dot(lightDir, viewDir);

	float h = length(p - planetCenter) - param.PlanetRadius;
	float3 rayleigh = RayleighCoefficient(param, h) * RayleiPhase(cos_theta);
	float3 mie = MieCoefficient(param, h) * MiePhase(param, cos_theta);

	return rayleigh + mie;
}

//这么映射有效利用了lut的空间，主要是cos_theta的采样范围并不是0到180°，因为超过一定限度采样方向就和地球表面相交，光全部衰减没了
void UvToTransmittanceLutParams(float bottomRadius, float topRadius, float2 uv, out float mu, out float r)
{
	float x_mu = uv.x;
	float x_r = uv.y;

	float H = sqrt(max(0.0f, topRadius * topRadius - bottomRadius * bottomRadius));
	float rho = H * x_r;
	r = sqrt(max(0.0f, rho * rho + bottomRadius * bottomRadius));

	float d_min = topRadius - r;
	float d_max = rho + H;
	float d = d_min + x_mu * (d_max - d_min);
	//通过GetTransmittanceLutUv里面对于d推导的等式的变换，其中H*H - rho*rho == topRadius * topRadius - r*r
	mu = d == 0.0f ? 1.0f : (H * H - rho * rho - d * d) / (2.0f * r * d);
	mu = clamp(mu, -1.0f, 1.0f);
}

float2 GetTransmittanceLutUv(float bottomRadius, float topRadius, float mu, float r)
{
	float H = sqrt(max(0.0f, topRadius * topRadius - bottomRadius * bottomRadius));
	float rho = sqrt(max(0.0f, r * r - bottomRadius * bottomRadius));

	//相似三角形，首先以r为斜边，利用对顶角构造一个直角三角形，然后连接球心到扫射线与大气顶部的交点，又构造一个直角三角形
	float discriminant = r * r * (mu * mu - 1.0f) + topRadius * topRadius;
	float d = max(0.0f, (-r * mu + sqrt(discriminant)));

	float d_min = topRadius - r;
	float d_max = rho + H;

	float x_mu = (d - d_min) / (d_max - d_min);
	float x_r = rho / H;

	return float2(x_mu, x_r);
}

float3 UVToViewDir(float2 uv)
{
	float theta = (1.0 - uv.y) * PI;
	float phi = (uv.x * 2 - 1) * PI;

	float x = sin(theta) * cos(phi);
	float z = sin(theta) * sin(phi);
	float y = cos(theta);

	return float3(x, y, z);
}

float2 ViewDirToUV(float3 v)
{
	//这里应该是因为asin和acos返回的值是-pi/2到pi/2，由于要归一化到0-1，后续的+0.5操作会影响sin变为cos，正好符合uv到view的映射
	float2 uv = float2(atan2(v.z, v.x), asin(v.y));
	uv /= float2(2.0 * PI, PI);
	uv += float2(0.5, 0.5);

	return uv;
}

// 查表计算任意点 p 沿着任意方向 dir 到大气层边缘的 transmittance
float3 TransmittanceToAtmosphere(in AtmosphereParameter param, float3 p, float3 dir, Texture2D lut, SamplerState spl)
{
	float3 planetCenter = float3(0, -param.PlanetRadius, 0);
	float bottomRadius = param.PlanetRadius;
	float topRadius = param.PlanetRadius + param.AtmosphereHeight;

	float3 upVector = normalize(p - planetCenter);
	float cos_theta = dot(upVector, dir);
	float r = length(p - planetCenter);

	float2 uv = GetTransmittanceLutUv(bottomRadius, topRadius, cos_theta, r);
	return lut.SampleLevel(spl, uv, 0).rgb;
}

// 积分计算任意两点 p1, p2 之间的 transmittance
float3 Transmittance(in AtmosphereParameter param, float3 p1, float3 p2)
{
	float3 planetCenter = float3(0, -param.PlanetRadius, 0);
	float3 dir = normalize(p2 - p1);
	float distance = length(p2 - p1);
	float ds = distance / float(N_SAMPLE);
	float3 sum = 0.0;
	float3 p = p1 + (dir * ds) * 0.5;

	for (int i = 0; i < N_SAMPLE; i++)
	{
		float h = length(p - planetCenter) - _PlanetRadius;

		float3 scattering = RayleighCoefficient(param, h) + MieCoefficient(param, h);
		float3 absorption = OzoneAbsorption(param, h) + MieAbsorption(param, h);
		float3 extinction = scattering + absorption;

		sum += extinction * ds;
		p += dir * ds;
	}

	return exp(-sum);
}

// 读取多重散射查找表
float3 GetMultiScattering(in AtmosphereParameter param, float3 p, float3 lightDir, Texture2D lut, SamplerState spl)
{
	float3 planetCenter = float3(0, -param.PlanetRadius, 0);
	float h = length(p - planetCenter) - param.PlanetRadius;
	float3 sigma_s = RayleighCoefficient(param, h) + MieCoefficient(param, h);

	float cosSunZenithAngle = dot(normalize(p - planetCenter), lightDir);
	float2 uv = float2(cosSunZenithAngle * 0.5 + 0.5, h / param.AtmosphereHeight);
	float3 G_ALL = lut.SampleLevel(spl, uv, 0).rgb;

	return G_ALL * sigma_s;
}

#endif