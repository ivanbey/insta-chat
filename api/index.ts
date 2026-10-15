import type { VercelRequest, VercelResponse } from '@vercel/node';

export default function handler(req: VercelRequest, res: VercelResponse) {
  return res.status(200).json({
    status: 'online',
    service: 'InstaChat API Gateway',
    timestamp: new Date().toISOString(),
  });
}
