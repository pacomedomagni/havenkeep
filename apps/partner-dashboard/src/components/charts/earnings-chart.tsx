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

interface EarningsChartProps {
  data?: { month: string; earnings: number }[];
}

const emptyData = Array.from({ length: 12 }, (_, i) => {
  const date = new Date();
  date.setMonth(date.getMonth() - (11 - i));
  return {
    month: date.toLocaleString('default', { month: 'short' }),
    earnings: 0,
  };
});

export default function EarningsChart({ data }: EarningsChartProps) {
  const chartData = data && data.length > 0 ? data : emptyData;

  return (
    <ResponsiveContainer width="100%" height={300}>
      <LineChart data={chartData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
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
