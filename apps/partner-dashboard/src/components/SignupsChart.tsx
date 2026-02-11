'use client'

import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'

interface SignupsChartProps {
  data: Array<{ date: string; signups: number }>
}

export default function SignupsChart({ data }: SignupsChartProps) {
  const formattedData = data.map(d => ({
    date: new Date(d.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    signups: d.signups,
  }))

  return (
    <div className="card">
      <h3 className="text-lg font-semibold text-white mb-4">Daily Signups (Last 30 Days)</h3>
      <ResponsiveContainer width="100%" height={300}>
        <LineChart data={formattedData}>
          <CartesianGrid strokeDasharray="3 3" stroke="#2A2A2A" />
          <XAxis
            dataKey="date"
            stroke="#707070"
            style={{ fontSize: '12px' }}
          />
          <YAxis
            stroke="#707070"
            style={{ fontSize: '12px' }}
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
          <Line
            type="monotone"
            dataKey="signups"
            stroke="#6C63FF"
            strokeWidth={2}
            dot={{ fill: '#6C63FF', r: 4 }}
            activeDot={{ r: 6 }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
