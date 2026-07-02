export interface PhotoRecord {
  id: string;
  originalImage: string; // base64 data URL，原始拍摄照片
  resultImage: string; // base64 data URL，AI 生成的白底贴纸（整张）
  cutoutImage?: string; // base64 PNG，抠掉背景后的单独贴纸（透明 + 白色模切边）
  timestamp: number;
  paperStyleID?: string; // 套用的相纸样式 id（见 lib/paperStyles）；缺失按默认 cream
}
