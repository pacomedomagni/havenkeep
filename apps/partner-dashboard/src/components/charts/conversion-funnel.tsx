'use client';

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from 'recharts';

const funnelData = [
  { stage: 'Referrals', count: 127, color: '#6C63FF' },
  { stage: 'Signups', count: 84, color: '#BB86FC' },
  { stage: 'Active', count: 62, color: '#4CAF50' },
  { stage: 'Premium', count: 28, color: '#FFC107' },
];

export default function ConversionFunnel() {
  return (
    <ResponsiveContainer width="100%" height={300}>
      <BarChart data={funnelData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#2A2A2A" />
        <XAxis
          dataKey="stage"
          stroke="#707070"
          fontSize={12}
          tickLine={false}
          axisLine={{ stroke: '#2A2A2A' }}
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
        <Bar dataKey="count" radius={[6, 6, 0, 0]}>
          {funnelData.map((entry, index) => (
            <Cell key={`cell-${index}`} fill={entry.color} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
