// 豆包 seedream 单次生成约需 20~35s，留足超时上限，避免请求挂死导致一直停在"冲印中"
const TIMEOUT_MS = 60_000;

export async function generateSticker(imageBase64: string): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const response = await fetch("/api/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ image: imageBase64 }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const err = await response.json().catch(() => ({}));
      throw new Error(err.error || "生成失败");
    }

    const data = await response.json();
    return data.image as string;
  } finally {
    clearTimeout(timer);
  }
}
