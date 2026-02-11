'use client';

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';

interface TopReferralsProps {
  data?: { code: string; conversions: number }[];
}

export default function TopReferrals({ data }: TopReferralsProps) {
  if (!data || data.length === 0) {
    return (
      <div className="flex items-center justify-center h-[300px] text-haven-text-tertiary text-sm">
        No referral data yet. Send your first gift to get started.
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={300}>
      <BarChart
        data={data}
        layout="vertical"
        margin={{ top: 5, right: 20, left: 20, bottom: 5 }}
      >
        <CartesianGrid strokeDasharray="3 3" stroke="#2A2A2A" horizontal={false} />
        <XAxis
          type="number"
          stroke="#707070"
          fontSize={12}
          tickLine={false}
          axisLine={{ stroke: '#2A2A2A' }}
          allowDecimals={false}
        />
        <YAxis
          type="category"
          dataKey="code"
          stroke="#707070"
          fontSize={11}
          tickLine={false}
          axisLine={{ stroke: '#2A2A2A' }}
          width={120}
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
        <Bar
          dataKey="conversions"
          fill="#BB86FC"
          radius={[0, 6, 6, 0]}
        />
      </BarChart>
    </ResponsiveContainer>
  );
}
