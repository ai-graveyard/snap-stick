/** @type {import('next').NextConfig} */
const nextConfig = {
  // 关闭以避免开发环境下摄像头初始化 effect 被双调用
  reactStrictMode: false,
  // 输出独立运行包，Docker 镜像只需拷贝 .next/standalone，体积最小
  output: "standalone",
};

module.exports = nextConfig;
