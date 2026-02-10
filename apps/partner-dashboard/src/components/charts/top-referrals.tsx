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

const topReferralCodes = [
  { code: 'HK-ABCD-1234', conversions: 18 },
  { code: 'HK-MNOP-3456', conversions: 14 },
  { code: 'HK-CDEF-0123', conversions: 11 },
  { code: 'HK-GHIJ-4567', conversions: 8 },
  { code: 'HK-KLMN-8901', conversions: 6 },
];

export default function TopReferrals() {
  return (
    <ResponsiveContainer width="100%" height={300}>
      <BarChart
        data={topReferralCodes}
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
