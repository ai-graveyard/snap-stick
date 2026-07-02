import { NextResponse } from "next/server";
import { checkRateLimit, getClientIp } from "@/lib/rateLimit";

// 固定提示词：图生图调用的是本项目自己付费的 API Key，绝不接受客户端传入的 prompt 覆盖，
// 否则任何人都能借这把 Key 生成任意内容
const STICKER_PROMPT =
  "把这张照片变成一张可爱的卡通贴纸，保留主体，明快配色，纯白背景纯色平涂，主体居中且四周留出白色边距、不要触碰画面边缘";

// 2K 输出对应的输入图裁得再大也不该超这个数量级，超出直接拒绝，防止超大 body 拖垮进程
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

export async function POST(request: Request) {
  try {
    const ip = getClientIp(request);
    const { allowed, retryAfterSeconds } = checkRateLimit(ip);
    if (!allowed) {
      return NextResponse.json(
        { error: "请求太频繁，请稍后再试" },
        { status: 429, headers: { "Retry-After": String(retryAfterSeconds) } }
      );
    }

    const contentLength = Number(request.headers.get("content-length") || 0);
    if (contentLength > MAX_IMAGE_BYTES) {
      return NextResponse.json({ error: "图片数据过大" }, { status: 413 });
    }

    const { image } = await request.json();

    if (!image || typeof image !== "string" || !image.startsWith("data:image/")) {
      return NextResponse.json({ error: "缺少图片数据" }, { status: 400 });
    }

    if (image.length > MAX_IMAGE_BYTES) {
      return NextResponse.json({ error: "图片数据过大" }, { status: 413 });
    }

    const apiKey = process.env.ARK_API_KEY;
    if (!apiKey) {
      return NextResponse.json({ error: "服务器配置错误" }, { status: 500 });
    }

    const response = await fetch("https://ark.cn-beijing.volces.com/api/v3/images/generations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "doubao-seedream-5-0-260128",
        prompt: STICKER_PROMPT,
        image: image,
        response_format: "url",
        size: "2K",
        sequential_image_generation: "disabled",
        watermark: true,
        stream: false,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Doubao API 错误:", response.status, errorText);
      return NextResponse.json(
        { error: `AI 生成失败: ${response.status}` },
        { status: response.status }
      );
    }

    const data = await response.json();
    const imageUrl = data.data?.[0]?.url;

    if (!imageUrl) {
      return NextResponse.json({ error: "AI 返回数据异常" }, { status: 500 });
    }

    // 代理下载图片，返回 base64 给前端（避免跨域和防盗链问题）
    const imageResponse = await fetch(imageUrl);
    const imageBuffer = await imageResponse.arrayBuffer();
    const base64 = Buffer.from(imageBuffer).toString("base64");
    const contentType = imageResponse.headers.get("content-type") || "image/png";

    return NextResponse.json({
      image: `data:${contentType};base64,${base64}`,
    });
  } catch (error) {
    console.error("生成接口异常:", error);
    return NextResponse.json({ error: "服务器内部错误" }, { status: 500 });
  }
}
