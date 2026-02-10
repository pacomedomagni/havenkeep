'use client';

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';

const monthlyEarnings = [
  { month: 'Apr', earnings: 320 },
  { month: 'May', earnings: 450 },
  { month: 'Jun', earnings: 280 },
  { month: 'Jul', earnings: 590 },
  { month: 'Aug', earnings: 720 },
  { month: 'Sep', earnings: 640 },
  { month: 'Oct', earnings: 890 },
  { month: 'Nov', earnings: 750 },
  { month: 'Dec', earnings: 1120 },
  { month: 'Jan', earnings: 980 },
  { month: 'Feb', earnings: 1340 },
  { month: 'Mar', earnings: 1240 },
];

export default function EarningsChart() {
  return (
    <ResponsiveContainer width="100%" height={300}>
      <LineChart data={monthlyEarnings} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#2A2A2A" />
        <XAxis
          dataKey="month"
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
          tickFormatter={(value) => `$${value}`}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: '#1E1E1E',
            border: '1px solid #2A2A2A',
            borderRadius: '8px',
            color: '#FFFFFF',
          }}
          labelStyle={{ color: '#B0B0B0' }}
          formatter={(value: number) => [`$${value}`, 'Earnings']}
        />
        <Line
          type="monotone"
          dataKey="earnings"
          stroke="#4CAF50"
          strokeWidth={2}
          dot={{ fill: '#4CAF50', strokeWidth: 0, r: 4 }}
          activeDot={{ r: 6, fill: '#4CAF50' }}
        />
      </LineChart>
    </ResponsiveContainer>
  );
}
