'use client';

import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';

// Mock data for last 30 days
const mockData = Array.from({ length: 30 }, (_, i) => {
  const date = new Date();
  date.setDate(date.getDate() - (29 - i));
  return {
    date: date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    referrals: Math.floor(Math.random() * 8) + 1,
  };
});

export default function ReferralChart() {
  return (
    <ResponsiveContainer width="100%" height={320}>
      <AreaChart data={mockData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
        <defs>
          <linearGradient id="referralGradient" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="#6C63FF" stopOpacity={0.3} />
            <stop offset="95%" stopColor="#6C63FF" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="#2A2A2A" />
        <XAxis
          dataKey="date"
          stroke="#707070"
          fontSize={12}
          tickLine={false}
          axisLine={{ stroke: '#2A2A2A' }}
          interval={4}
        />
        <YAxis
          stroke="#707070"
          fontSize={12}
          tickLine={false}
          axisLine={{ stroke: '#2A2A2A' }}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: '#1E1E1E',
            border: '1px solid #2A2A2A',
            borderRadius: '8px',
            color: '#FFFFFF',
          }}
          labelStyle={{ color: '#B0B0B0' }}
        />
        <Area
          type="monotone"
          dataKey="referrals"
          stroke="#6C63FF"
          strokeWidth={2}
          fill="url(#referralGradient)"
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
