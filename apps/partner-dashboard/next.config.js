/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  // Proxy API calls to the upstream API. API_UPSTREAM_URL is read at
  // container start time (not build time), so a single dashboard image
  // can be pointed at staging or production without rebuilding.
  async rewrites() {
    const upstream = process.env.API_UPSTREAM_URL;
    if (!upstream) return [];
    return [
      {
        source: '/api/v1/:path*',
        destination: `${upstream.replace(/\/$/, '')}/api/v1/:path*`,
      },
    ];
  },
}

module.exports = nextConfig
